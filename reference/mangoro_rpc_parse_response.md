# Parse an RPC response message

Parse an RPC response message

## Usage

``` r
mangoro_rpc_parse_response(response)
```

## Arguments

- response:

  Raw vector containing the RPC response

## Value

A list with components: type, func_name, error_msg, data
