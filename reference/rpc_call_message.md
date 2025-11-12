# Create an RPC function call message

Create an RPC function call message

## Usage

``` r
rpc_call_message(func_name, data)
```

## Arguments

- func_name:

  Name of the function to call

- data:

  Data frame or Arrow stream to send as arguments

## Value

A raw vector containing the RPC call message
