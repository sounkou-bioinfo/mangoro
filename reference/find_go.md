# Find the path to the Go executable

Locates a usable `go` binary for runtime IPC helpers. Resolution order:

1.  `options(mangoro.go_path)`

2.  `Sys.getenv("MANGORO_GO")`

3.  `Sys.which("go")`

Candidates are validated by running `go version`. Errors reference the
detected OS/arch using user-friendly labels (e.g., macOS arm64).

## Usage

``` r
find_go()
```

## Value

Path to the Go binary
