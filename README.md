
# R/Go IPC with Nanomsg Next Gen

## Test echo server setup

``` r
library(mangoro)
library(nanonext)
library(processx)

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
#> [1] "/tmp/RtmpQ3lNvu/file1be9d2a666220"

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
