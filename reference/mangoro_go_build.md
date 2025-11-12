# Compile a Go source file using the vendored dependencies

Compile a Go source file using the vendored dependencies

## Usage

``` r
mangoro_go_build(src, out, gomaxprocs = 1, ...)
```

## Arguments

- src:

  Path to the Go source file

- out:

  Path to the output binary

- gomaxprocs:

  Number of threads for Go build (sets GOMAXPROCS env variable)

- ...:

  Additional arguments to pass to Go build

## Value

Path to the compiled binary
