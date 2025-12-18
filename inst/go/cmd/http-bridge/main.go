// HTTP server controller exposed via mangoro RPC (REQ/REP + Arrow IPC).
// Registers start/stop/status RPCs; startServer supports static dir, prefix,
// CORS/COOP headers, and optional TLS. WebSocket proxy stub included.
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"go.nanomsg.org/mangos/v3"
	"go.nanomsg.org/mangos/v3/protocol/rep"
	_ "go.nanomsg.org/mangos/v3/transport/ipc"

	"mangoro.local/pkg/rgoipc"

	"github.com/apache/arrow/go/v18/arrow"
	"github.com/apache/arrow/go/v18/arrow/array"
	"github.com/apache/arrow/go/v18/arrow/memory"
)

var (
	httpServer *http.Server
	serverLog  *log.Logger
)

func die(format string, v ...interface{}) {
	fmt.Fprintf(os.Stderr, format+"\n", v...)
	os.Exit(1)
}

// startServerHandler starts an HTTP server with given configuration
func startServerHandler(input arrow.Record) (arrow.Record, error) {
	if input.NumCols() < 9 {
		return nil, fmt.Errorf("expected 9 columns, got %d", input.NumCols())
	}

	addrCol := input.Column(0).(*array.String)
	dirCol := input.Column(1).(*array.String)
	prefixCol := input.Column(2).(*array.String)
	corsCol := input.Column(3).(*array.Boolean)
	coopCol := input.Column(4).(*array.Boolean)
	tlsCol := input.Column(5).(*array.Boolean)
	certCol := input.Column(6).(*array.String)
	keyCol := input.Column(7).(*array.String)
	silentCol := input.Column(8).(*array.Boolean)

	if addrCol.Len() == 0 {
		return nil, fmt.Errorf("no server address provided")
	}

	addr := addrCol.Value(0)
	dir := "."
	if dirCol.Len() > 0 && !dirCol.IsNull(0) {
		dir = dirCol.Value(0)
	}
	prefix := "/"
	if prefixCol.Len() > 0 && !prefixCol.IsNull(0) {
		prefix = prefixCol.Value(0)
	}
	cors := corsCol.Len() > 0 && !corsCol.IsNull(0) && corsCol.Value(0)
	coop := coopCol.Len() > 0 && !coopCol.IsNull(0) && coopCol.Value(0)
	useTLS := tlsCol.Len() > 0 && !tlsCol.IsNull(0) && tlsCol.Value(0)
	certFile := ""
	if certCol.Len() > 0 && !certCol.IsNull(0) {
		certFile = certCol.Value(0)
	}
	keyFile := ""
	if keyCol.Len() > 0 && !keyCol.IsNull(0) {
		keyFile = keyCol.Value(0)
	}
	silent := silentCol.Len() > 0 && !silentCol.IsNull(0) && silentCol.Value(0)

	if httpServer != nil {
		return buildResponse("error", "HTTP server already running")
	}

	var logWriter io.Writer
	if silent {
		logWriter = io.Discard
	} else {
		logWriter = os.Stdout
	}
	serverLog = log.New(logWriter, "[mangoro http] ", log.LstdFlags)

	absDir, err := filepath.Abs(dir)
	if err != nil {
		return buildResponse("error", fmt.Sprintf("invalid directory: %v", err))
	}

	mux := http.NewServeMux()
	fileHandler := http.FileServer(http.Dir(absDir))
	if cors {
		fileHandler = enableCORS(fileHandler)
	}
	if coop {
		fileHandler = enableCOOP(fileHandler)
	}
	fileHandler = serveLogger(serverLog, fileHandler)

	if prefix == "/" {
		mux.Handle("/", fileHandler)
	} else {
		mux.Handle(prefix+"/", http.StripPrefix(prefix, fileHandler))
	}

	// WebSocket proxy stub route (expand as needed)
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "websocket proxy not implemented", http.StatusNotImplemented)
	})

	httpServer = &http.Server{
		Addr:    addr,
		Handler: mux,
	}
	if useTLS {
		httpServer.TLSConfig = &tls.Config{
			MinVersion: tls.VersionTLS12,
		}
	}

	errChan := make(chan error, 1)
	go func() {
		var err error
		if useTLS {
			if certFile == "" || keyFile == "" {
				errChan <- fmt.Errorf("certificate and key required for TLS")
				return
			}
			serverLog.Printf("Starting HTTPS on %s serving %s at %s", addr, absDir, prefix)
			err = httpServer.ListenAndServeTLS(certFile, keyFile)
		} else {
			serverLog.Printf("Starting HTTP on %s serving %s at %s", addr, absDir, prefix)
			err = httpServer.ListenAndServe()
		}
		if err != nil && err != http.ErrServerClosed {
			errChan <- err
		}
	}()

	select {
	case err := <-errChan:
		httpServer = nil
		return buildResponse("error", fmt.Sprintf("failed to start server: %v", err))
	case <-time.After(500 * time.Millisecond):
	}

	return buildResponse("ok", fmt.Sprintf("HTTP server started on %s", addr))
}

func stopServerHandler(input arrow.Record) (arrow.Record, error) {
	if httpServer == nil {
		return buildResponse("error", "No HTTP server is running")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(ctx); err != nil {
		return buildResponse("error", fmt.Sprintf("shutdown failed: %v", err))
	}
	httpServer = nil
	serverLog.Printf("HTTP server stopped")
	return buildResponse("ok", "HTTP server stopped")
}

func statusHandler(input arrow.Record) (arrow.Record, error) {
	if httpServer == nil {
		return buildResponse("status", "stopped")
	}
	return buildResponse("status", "running at "+httpServer.Addr)
}

func buildResponse(status, message string) (arrow.Record, error) {
	pool := memory.NewGoAllocator()
	statusBuilder := array.NewStringBuilder(pool)
	messageBuilder := array.NewStringBuilder(pool)
	defer statusBuilder.Release()
	defer messageBuilder.Release()

	statusBuilder.Append(status)
	messageBuilder.Append(message)

	fields := []arrow.Field{
		{Name: "status", Type: arrow.BinaryTypes.String},
		{Name: "message", Type: arrow.BinaryTypes.String},
	}
	schema := arrow.NewSchema(fields, nil)

	arrStatus := statusBuilder.NewArray()
	arrMsg := messageBuilder.NewArray()
	defer arrStatus.Release()
	defer arrMsg.Release()

	cols := []arrow.Array{arrStatus, arrMsg}
	rec := array.NewRecord(schema, cols, 1)
	return rec, nil
}

func enableCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, Range")
		w.Header().Set("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func enableCOOP(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cross-Origin-Opener-Policy", "same-origin")
		next.ServeHTTP(w, r)
	})
}

func serveLogger(l *log.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		l.Printf("%s %s", r.Method, r.URL.Path)
		next.ServeHTTP(w, r)
	})
}

func main() {
	if len(os.Args) != 2 {
		die("Usage: %s <ipc_path>", os.Args[0])
	}
	url := os.Args[1]

	// Graceful shutdown on SIGINT/SIGTERM
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	registry := rgoipc.NewRegistry()
	// Return type shared by handlers: struct{status string, message string}
	returnType := rgoipc.TypeSpec{
		Type: rgoipc.TypeStruct,
		StructDef: &rgoipc.StructDef{
			Fields: []rgoipc.FieldDef{
				{Name: "status", Type: rgoipc.TypeSpec{Type: rgoipc.TypeString}},
				{Name: "message", Type: rgoipc.TypeSpec{Type: rgoipc.TypeString}},
			},
		},
	}

	err := registry.Register("startServer", startServerHandler, rgoipc.FunctionSignature{
		Args: []rgoipc.ArgSpec{
			{Name: "addr", Type: rgoipc.TypeSpec{Type: rgoipc.TypeString}},
			{Name: "dir", Type: rgoipc.TypeSpec{Type: rgoipc.TypeString}},
			{Name: "prefix", Type: rgoipc.TypeSpec{Type: rgoipc.TypeString}},
			{Name: "cors", Type: rgoipc.TypeSpec{Type: rgoipc.TypeBool}},
			{Name: "coop", Type: rgoipc.TypeSpec{Type: rgoipc.TypeBool}},
			{Name: "tls", Type: rgoipc.TypeSpec{Type: rgoipc.TypeBool}},
			{Name: "cert", Type: rgoipc.TypeSpec{Type: rgoipc.TypeString, Nullable: true}},
			{Name: "key", Type: rgoipc.TypeSpec{Type: rgoipc.TypeString, Nullable: true}},
			{Name: "silent", Type: rgoipc.TypeSpec{Type: rgoipc.TypeBool}},
		},
		ReturnType: returnType,
		Vectorized: false,
		Metadata:   map[string]string{"description": "Start HTTP server"},
	})
	if err != nil {
		die("register startServer failed: %s", err)
	}

	err = registry.Register("stopServer", stopServerHandler, rgoipc.FunctionSignature{
		Args:       []rgoipc.ArgSpec{},
		ReturnType: returnType,
		Vectorized: false,
		Metadata:   map[string]string{"description": "Stop HTTP server"},
	})
	if err != nil {
		die("register stopServer failed: %s", err)
	}

	err = registry.Register("serverStatus", statusHandler, rgoipc.FunctionSignature{
		Args:       []rgoipc.ArgSpec{},
		ReturnType: returnType,
		Vectorized: false,
		Metadata:   map[string]string{"description": "HTTP server status"},
	})
	if err != nil {
		die("register serverStatus failed: %s", err)
	}

	// Setup REP socket
	sock, err := rep.NewSocket()
	if err != nil {
		die("can't get new rep socket: %s", err)
	}
	if err = sock.Listen(url); err != nil {
		die("can't listen on rep socket: %s", err)
	}

	fmt.Printf("HTTP controller listening on %s\n", url)

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		msgBytes, err := sock.Recv()
		if err != nil {
			fmt.Fprintf(os.Stderr, "receive error: %s\n", err)
			continue
		}

		msg, err := rgoipc.UnmarshalRPCMessage(msgBytes)
		if err != nil {
			fmt.Fprintf(os.Stderr, "unmarshal error: %s\n", err)
			sendError(sock, "", fmt.Sprintf("unmarshal error: %s", err))
			continue
		}

		switch msg.Type {
		case rgoipc.MsgTypeManifest:
			handleManifest(sock, registry)
		case rgoipc.MsgTypeCall:
			handleCall(sock, registry, msg)
		default:
			sendError(sock, "", "unknown message type")
		}
	}
}

func handleManifest(sock mangos.Socket, registry *rgoipc.Registry) {
	manifest, err := registry.Manifest()
	if err != nil {
		sendError(sock, "", fmt.Sprintf("manifest error: %s", err))
		return
	}
	response := &rgoipc.RPCMessage{
		Type:      rgoipc.MsgTypeManifest,
		ArrowData: manifest,
	}
	sock.Send(response.Marshal())
}

func handleCall(sock mangos.Socket, registry *rgoipc.Registry, msg *rgoipc.RPCMessage) {
	fn, ok := registry.Get(msg.FuncName)
	if !ok {
		sendError(sock, msg.FuncName, "function not found")
		return
	}

	reader, err := rgoipc.NewArrowReader(msg.ArrowData)
	if err != nil {
		sendError(sock, msg.FuncName, fmt.Sprintf("arrow read error: %s", err))
		return
	}
	defer reader.Release()

	var inputRecord arrow.Record
	if reader.Next() {
		inputRecord = reader.Record()
		defer inputRecord.Release()
	} else {
		// empty record
		inputRecord = array.NewRecord(arrow.NewSchema([]arrow.Field{}, nil), []arrow.Array{}, 0)
		defer inputRecord.Release()
	}

	result, err := fn.Handler(inputRecord)
	if err != nil {
		sendError(sock, msg.FuncName, fmt.Sprintf("execution error: %s", err))
		return
	}
	defer result.Release()

	buf, err := rgoipc.WriteArrowRecord(result)
	if err != nil {
		sendError(sock, msg.FuncName, fmt.Sprintf("arrow write error: %s", err))
		return
	}

	response := &rgoipc.RPCMessage{
		Type:      rgoipc.MsgTypeResult,
		FuncName:  msg.FuncName,
		ArrowData: buf,
	}
	sock.Send(response.Marshal())
}

func sendError(sock mangos.Socket, funcName, errMsg string) {
	response := &rgoipc.RPCMessage{
		Type:     rgoipc.MsgTypeError,
		FuncName: funcName,
		ErrorMsg: errMsg,
	}
	sock.Send(response.Marshal())
}
