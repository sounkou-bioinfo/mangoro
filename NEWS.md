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