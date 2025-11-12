# rgoipc - R/Go IPC Package

The `rgoipc` package provides a framework for building RPC servers in Go that can be called from R using Arrow IPC serialization and nanomsg messaging.

## Overview

This package enables:
- Type-safe function registration with Arrow schema validation
- Function discovery (Go servers broadcast available functions to R)
- Minimal overhead RPC protocol for function calls
- Vectorized operations with batch processing support

## Architecture

```
R Process                    Go Process
---------                    ----------
nanonext + nanoarrow    <->  mangos + arrow-go + rgoipc
```

The communication is entirely through separate processes connected via nanomsg IPC sockets. No CGo is used in the Go process.

## Core Types

### Registry

The `Registry` holds registered functions that can be called from R:

```go
registry := rgoipc.NewRegistry()
```

### Function Registration

Register a function with type signatures:

```go
err := registry.Register("add", addHandler, rgoipc.FunctionSignature{
    Args: []rgoipc.ArgSpec{
        {Name: "x", Type: rgoipc.TypeSpec{Type: rgoipc.TypeFloat64, Nullable: true}},
        {Name: "y", Type: rgoipc.TypeSpec{Type: rgoipc.TypeFloat64, Nullable: true}},
    },
    ReturnType: rgoipc.TypeSpec{Type: rgoipc.TypeFloat64, Nullable: true},
    Vectorized: true,
})
```

### Function Handler

Implement the `FunctionHandler` interface:

```go
func addHandler(input arrow.Record) (arrow.Record, error) {
    x := input.Column(0).(*array.Float64)
    y := input.Column(1).(*array.Float64)
    
    // Build result
    builder := array.NewFloat64Builder(memory.NewGoAllocator())
    defer builder.Release()
    
    for i := 0; i < x.Len(); i++ {
        if x.IsNull(i) || y.IsNull(i) {
            builder.AppendNull()
        } else {
            builder.Append(x.Value(i) + y.Value(i))
        }
    }
    
    result := builder.NewArray()
    defer result.Release()
    
    schema := arrow.NewSchema([]arrow.Field{
        {Name: "result", Type: arrow.PrimitiveTypes.Float64}
    }, nil)
    
    return array.NewRecord(schema, []arrow.Array{result}, int64(result.Len())), nil
}
```

## RPC Protocol

### Message Types

- `MsgTypeManifest` (0): Request function list from Go → R
- `MsgTypeCall` (1): Call function from R → Go
- `MsgTypeResult` (2): Return result from Go → R
- `MsgTypeError` (3): Return error from Go → R

### Wire Format

```
[type:1byte][name_len:4bytes][name][error_len:4bytes][error][arrow_ipc_data]
```

## Supported Types

The following Arrow types map to R types:

| rgoipc Type | Arrow Type | R Type |
|-------------|------------|--------|
| TypeInt32   | int32      | integer |
| TypeInt64   | int64      | integer (large) |
| TypeFloat64 | float64    | numeric |
| TypeString  | string     | character |
| TypeBool    | bool       | logical |
| TypeList    | list       | list |
| TypeStruct  | struct     | data.frame |

## Example Server

See [cmd/rpc-example/main.go](../../cmd/rpc-example/main.go) for a complete example.

Basic server structure:

```go
func main() {
    registry := rgoipc.NewRegistry()
    
    // Register functions
    registry.Register("add", addHandler, signature)
    
    // Setup socket
    sock, _ := rep.NewSocket()
    sock.Listen(url)
    
    // Handle requests
    for {
        msgBytes, _ := sock.Recv()
        msg, _ := rgoipc.UnmarshalRPCMessage(msgBytes)
        
        switch msg.Type {
        case rgoipc.MsgTypeManifest:
            handleManifest(sock, registry)
        case rgoipc.MsgTypeCall:
            handleCall(sock, registry, msg)
        }
    }
}
```

## R Client Usage

From R, you can call registered Go functions using the mangoro package helpers and the RPC protocol. See the README.Rmd for examples.

## Testing

Run tests with:

```bash
cd inst/go
go test ./pkg/rgoipc/...
```
