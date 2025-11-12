# Start an HTTP file server via RPC

Start an HTTP file server via RPC

## Usage

``` r
mangoro_http_start(
  sock,
  addr,
  dir = ".",
  prefix = "/",
  cors = FALSE,
  coop = FALSE,
  tls = FALSE,
  silent = FALSE
)
```

## Arguments

- sock:

  A nanonext socket connected to the HTTP server controller

- addr:

  Address to bind server to (e.g., "127.0.0.1:8080")

- dir:

  Directory to serve (default: current directory)

- prefix:

  URL prefix for the server (default: "/")

- cors:

  Enable CORS headers (default: FALSE)

- coop:

  Enable Cross-Origin-Opener-Policy (default: FALSE)

- tls:

  Enable TLS (default: FALSE)

- silent:

  Suppress server logs (default: FALSE)

## Value

List with status and message
