# Call a remote function via RPC

Call a remote function via RPC

## Usage

``` r
rpc_call(sock, func_name, data)
```

## Arguments

- sock:

  A nanonext socket connected to the RPC server

- func_name:

  Name of the function to call

- data:

  Data frame or Arrow stream to send as arguments

## Value

A data frame with the result
