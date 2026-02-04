# Find the path to the Go executable

Locates a usable `go` binary for runtime IPC helpers. Resolution order:

1.  `options(mangoro.go_path)`

2.  `Sys.getenv("MANGORO_GO")`

3.  `PATH` entries and platform defaults via
    [`go_binary_candidates()`](https://sounkou-bioinfo.github.io/mangoro/reference/go_binary_candidates.md)

Candidates are validated by running `go version` and checking the
minimum required Go version from the vendored `go.mod`. Errors reference
the detected OS/arch using user-friendly labels (e.g., macOS arm64).

## Usage

``` r
mangoro_min_go_version()
```

## Value

Path to the Go binary
