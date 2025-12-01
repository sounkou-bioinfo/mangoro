# Compile a Go source file using the vendored dependencies

Compiles a Go source file using the vendored dependencies from the
mangoro package.

To comply with CRAN policy, this function temporarily redirects several
environment variables to prevent Go from writing to user directories:

- `HOME` is set to a temporary directory because Go's telemetry system
  (introduced in Go 1.23+) writes data to `~/.config/go/telemetry` using
  `os.UserConfigDir()`, which cannot be disabled via environment
  variables alone.

- `GOCACHE` is set to a temporary directory to prevent build cache
  writes to `~/.cache/go-build`.

- `GOENV` is set to a temporary file to prevent config writes to
  `~/.config/go/env`.

All environment variables are restored and temporary directories cleaned
up after the build completes.

## Usage

``` r
mangoro_go_build(src, out, gomaxprocs = 1, gocache = NULL, ...)
```

## Arguments

- src:

  Path to the Go source file

- out:

  Path to the output binary

- gomaxprocs:

  Number of threads for Go build (sets GOMAXPROCS env variable)

- gocache:

  Path to Go build cache directory. If NULL (default), uses a temporary
  directory to comply with CRAN policy. Set to NA to use the default Go
  cache location.

- ...:

  Additional arguments to pass to Go build

## Value

Path to the compiled binary

## See also

<https://go.dev/doc/telemetry> for Go telemetry documentation
