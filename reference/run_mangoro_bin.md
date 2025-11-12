# Run a mangoro Go binary with arguments

Run a mangoro Go binary with arguments

## Usage

``` r
run_mangoro_bin(name, args = character(), ...)
```

## Arguments

- name:

  Name of the binary (e.g. "echo")

- args:

  Arguments to pass to the binary

- ...:

  Additional arguments passed to processx::process\$new

## Value

A processx process object
