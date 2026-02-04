# Determine candidate Go binaries

Builds a list of candidate `go` paths from package options, environment
variables, PATH entries, and platform-specific defaults. This function
does not validate candidates.

## Usage

``` r
go_binary_candidates()
```

## Value

Character vector of candidate Go binary paths
