
<p align="center">
<img src="inst/docs/logo.svg" alt="mangoro hexsticker" width="180"/>
</p>

[![mangoro status
badge](https://sounkou-bioinfo.r-universe.dev/mangoro/badges/version)](https://sounkou-bioinfo.r-universe.dev/mangoro)

# mangoro

R/Go IPC with Nanomsg Next Gen.

## What is mangoro?

We vendor the [mangos/v3](https://github.com/nanomsg/mangos) Go package
for IPC between R and Go processes using the `nanonext` R package. The
package provides helper functions to build Go binaries that use mangos
for IPC, and to find and run those binaries from R. This is a basic
setup that can be used as a starting point for more complex R/Go IPC
applications.

## Test echo server setup

``` r
library(mangoro)
library(nanonext)
library(processx)

# vendored mangos version
get_mangos_version()
#> [1] "v3.4.3-0.20250905144305-2c434adf4860"


# Create a unique IPC path for the test
ipc_url <- create_ipc_path()

# Start echo server in background
bin_path <- find_mangoro_bin("echo")
echo_proc <- processx::process$new(bin_path, args = ipc_url)
Sys.sleep(1) # Give server time to start

# Connect as client and test echo
sock <- nanonext::socket("req", dial = ipc_url)
msg <- "hello from R"
nanonext::send(sock, msg)
#> [1] 0
reply <- nanonext::recv(sock)
reply
#> [1] "hello from R"
# Cleanup
close(sock)
echo_proc$kill()
#> [1] TRUE
```

## Test on-the-fly Go compilation and echo

``` r

go_echo_code <- '
package main
import (
  "os"
  "go.nanomsg.org/mangos/v3/protocol/rep"
  _ "go.nanomsg.org/mangos/v3/transport/ipc"
)
func main() {
  url := os.Args[1]
  sock, _ := rep.NewSocket()
  sock.Listen(url)
  for {
    msg, _ := sock.Recv()
    sock.Send(msg)
  }
}
'

tmp_go <- tempfile(fileext = ".go")
writeLines(go_echo_code, tmp_go)

tmp_bin <- tempfile()
mangoro_go_build(tmp_go, tmp_bin)
#> [1] "/tmp/RtmpierTMo/file25b005f9ff8b9"

ipc_url <- create_ipc_path()
echo_proc <- processx::process$new(tmp_bin, args = ipc_url)
Sys.sleep(1)

sock <- nanonext::socket("req", dial = ipc_url)
msg <- "hello from R (compiled)"
nanonext::send(sock, msg)
#> [1] 0
reply <- nanonext::recv(sock)
reply
#> [1] "hello from R (compiled)"
close(sock)
echo_proc$kill()
#> [1] TRUE
```
