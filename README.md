
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

## On-the-fly Go compilation and echo

``` r

library(mangoro)
library(nanonext)
library(processx)

# vendored mangos version
get_mangos_version()
#> [1] "v3.4.3-0.20250905144305-2c434adf4860"
go_echo_code <- paste(
  'package main',
  'import (',
  '  "os"',
  '  "go.nanomsg.org/mangos/v3/protocol/rep"',
  '  _ "go.nanomsg.org/mangos/v3/transport/ipc"',
  ')',
  'func main() {',
  '  url := os.Args[1]',
  '  sock, _ := rep.NewSocket()',
  '  sock.Listen(url)',
  '  for {',
  '    msg, _ := sock.Recv()',
  '    newMsg := append(msg, []byte(" [echoed by Go]")...)',
  '    sock.Send(newMsg)',
  '  }',
  '}',
  sep = "\n"
)

tmp_go <- tempfile(fileext = ".go")
writeLines(go_echo_code, tmp_go)

tmp_bin <- tempfile()
mangoro_go_build(tmp_go, tmp_bin)
#> [1] "/tmp/RtmpUiB1gb/file55d6421a311e6"

ipc_url <- create_ipc_path()
ipc_url
#> [1] "ipc:///tmp/RtmpUiB1gb/mangoro-echo55d6459cad79f.ipc"
echo_proc <- processx::process$new(tmp_bin, args = ipc_url)
Sys.sleep(1)
echo_proc$is_alive()
#> [1] TRUE
sock <- nanonext::socket("req", dial = ipc_url)
msg <- charToRaw("hello from R")
nanonext::send(sock, msg, mode = "raw")
#> [1] 0
nanonext::recv(sock, mode = "raw") |> rawToChar()
#> [1] "hello from R [echoed by Go]"
close(sock)
echo_proc$kill()
#> [1] TRUE
```
