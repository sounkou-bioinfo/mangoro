
<p align="center">
<svg width="180" height="208" viewBox="0 0 300 346" xmlns="http://www.w3.org/2000/svg">
<polygon points="150,10 290,87 290,259 150,336 10,259 10,87"
           fill="#ffe066" stroke="#f9a602" stroke-width="8"/>
<ellipse cx="170" cy="180" rx="70" ry="100" fill="#f9a602" stroke="#e17009" stroke-width="6"/>
<ellipse cx="200" cy="140" rx="18" ry="35" fill="#fffbe6" opacity="0.5"/>
<ellipse cx="120" cy="90" rx="35" ry="15" fill="#4caf50" stroke="#357a38" stroke-width="4" transform="rotate(-20 120 90)"/>
<text x="150" y="295" font-family="Montserrat, Arial, sans-serif" font-size="36" fill="#357a38" text-anchor="middle" font-weight="bold" letter-spacing="2">
mangoro </text>
</svg>
</p>

[![mangoro status
badge](https://sounkou-bioinfo.r-universe.dev/mangoro/badges/version)](https://sounkou-bioinfo.r-universe.dev/mangoro)

# mangoro

R/Go IPC with Nanomsg Next Gen.

## What is mangoro?

We vendore the [mangos/v3](https://github.com/nanomsg/mangos) Go package
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
#> [1] "/tmp/RtmplGSuR3/file24d9152dc5fac"

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
