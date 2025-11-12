# mangoro 0.2.1

## RPC Interface

- New `rgoipc` Go package for type-safe function registration with Arrow schema validation
- RPC protocol wrapping Arrow IPC data with function call envelope
- RPC helper functions: `mangoro_rpc_get_manifest()`, `mangoro_rpc_call()`, `mangoro_rpc_send()`, `mangoro_rpc_recv()`, `mangoro_rpc_parse_response()`
- RPC example server demonstrating function registration (add, echoString functions)
- HTTP file server with RPC control interface (start/stop/status commands)
- Helper functions for HTTP server control: `mangoro_http_start()`, `mangoro_http_stop()`, `mangoro_http_status()`

## Examples

- Complete RPC function registration and calling example in README
- HTTP server RPC control demonstration with server output capture
- Arrow IPC-based RPC communication examples

# mangoro 0.2.0

## Initial Release

- R/Go IPC using Nanomsg Next Gen (mangos v3, nanonext)
- Vendored Go dependencies for reproducible builds
- Helper functions to build and run Go binaries from R
- Example echo server and on-the-fly Go compilation from R
- Platform-correct IPC path helpers
- Designed for extensibility and cross-platform use
- We do not cgo's c-shared mode to avoid loading multiple Go runtimes in the same R session

## Arrow Go IPC Support

- Add Arrow Go IPC roundtrip example and support: send and receive Arrow IPC streams between R and Go using nanoarrow and arrow-go.
- New function: `get_arrow_go_version()` to report the vendored Arrow Go version.