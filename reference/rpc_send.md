# Send a message with retries

Send a message with retries

## Usage

``` r
rpc_send(sock, msg, max_attempts = 20)
```

## Arguments

- sock:

  A nanonext socket

- msg:

  Message to send (raw vector)

- max_attempts:

  Maximum number of retry attempts (default 20)

## Value

The result from nanonext::send
