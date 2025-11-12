# Receive a message with retries

Receive a message with retries

## Usage

``` r
rpc_recv(sock, max_attempts = 20)
```

## Arguments

- sock:

  A nanonext socket

- max_attempts:

  Maximum number of retry attempts (default 20)

## Value

The received message as a raw vector
