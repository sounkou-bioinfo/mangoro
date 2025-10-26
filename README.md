
<p align="center">
<img src="inst/docs/logo.svg" alt="mangoro hexsticker" width="180"/>
</p>

[![mangoro status
badge](https://sounkou-bioinfo.r-universe.dev/mangoro/badges/version)](https://sounkou-bioinfo.r-universe.dev/mangoro)

# mangoro

R/Go IPC with Nanomsg Next Gen.

## What is mangoro?

Beside being the way mangos is said in
[bambara](https://bm.wikipedia.org/wiki/Mangoro) (derived from portugese
as it happens), in this package we vendor the
[mangos/v3](https://github.com/nanomsg/mangos) and
[arrow-go](https://github.com/apache/arrow-go) Go packages for IPC
between R and Go processes using the `nanonext` and `nanoarrow` R
packages on the R side. The package provides helper functions to build
Go binaries that use mangos and Arrow for IPC. This is a basic setup
that can be used as a starting point for more complex R/Go IPC
applications. In our opinion, this approach avoids the complexities and
limitations of cgo’s c-shared mode, which can lead to issues with
loading multiple Go runtimes in the same R session as discussed in this
R-package-devel mailing list thread: [CRAN Policy on Go using
Packages](https://hypatia.math.ethz.ch/pipermail/r-package-devel/2025q4/012067.html).

## On-the-fly Go compilation and echo

Compile some go code on-the-fly from R using the `mangoro_go_build()`
function. This uses the vendored go code in
[inst/go/vendor](inst/go/vendor)

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
#> [1] "GOMAXPROCS=1 /usr/lib/go-1.22/bin/go 'build' '-mod=vendor' '-o' '/tmp/Rtmp5gaIfB/file9c4b2280dc59e' '/tmp/Rtmp5gaIfB/file9c4b23486a461.go'"
#> [1] "/tmp/Rtmp5gaIfB/file9c4b2280dc59e"
```

create IPC path and send/receive message

``` r
ipc_url <- create_ipc_path()
ipc_url
#> [1] "ipc:///tmp/Rtmp5gaIfB/mangoro-echo9c4b21c75a8ad.ipc"
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

## Arrow IPC with nanoarrow for serialization

Compile go code this time that uses Arrow IPC for (de)serialization
between R and Go.

``` r
library(nanoarrow)

cfg <- nanonext::serial_config(
  "ArrowTabular",
  nanoarrow::write_nanoarrow,
  nanoarrow::read_nanoarrow
)
ipc_url <- create_ipc_path()
go_code <- '
package main
import (
  "os"
  "bytes"
  "fmt"
  "go.nanomsg.org/mangos/v3/protocol/rep"
  _ "go.nanomsg.org/mangos/v3/transport/ipc"
  "github.com/apache/arrow/go/v18/arrow/ipc"
  "github.com/apache/arrow/go/v18/arrow/memory"
)
func main() {
  url := os.Args[1]
  sock, _ := rep.NewSocket()
  sock.Listen(url)
  for {
    msg, _ := sock.Recv()
    reader, err := ipc.NewReader(bytes.NewReader(msg), ipc.WithAllocator(memory.DefaultAllocator))
    if err != nil {
      fmt.Println("Arrow IPC error:", err)
      continue
    }
    var buf bytes.Buffer
    writer := ipc.NewWriter(&buf, ipc.WithSchema(reader.Schema()))
    for reader.Next() {
      rec := reader.Record()
      fmt.Println(rec)
      if err := writer.Write(rec); err != nil {
        fmt.Println("Arrow IPC write error:", err)
      }
      rec.Release()
    }
    if err := writer.Close(); err != nil {
      fmt.Println("Arrow IPC writer close error:", err)
    }
    reader.Release()
    sock.Send(buf.Bytes())
  }
}
'
tmp_go <- tempfile(fileext = ".go")
writeLines(go_code, tmp_go)
tmp_bin <- tempfile()
mangoro_go_build(tmp_go, tmp_bin)
#> [1] "GOMAXPROCS=1 /usr/lib/go-1.22/bin/go 'build' '-mod=vendor' '-o' '/tmp/Rtmp5gaIfB/file9c4b21ae3a017' '/tmp/Rtmp5gaIfB/file9c4b265a29cfb.go'"
#> [1] "/tmp/Rtmp5gaIfB/file9c4b21ae3a017"

echo_proc <- processx::process$new(tmp_bin, args = ipc_url, stdout = "|", stderr = "|"  )
Sys.sleep(3)
```

Configure the socket and send/receive an Arrow IPC data. Note that we
use a loop with retries to handle potential timing issues when the Go
echo server is not yet ready to receive messages.

``` r
echo_proc$is_alive()
#> [1] TRUE
sock <- nanonext::socket("req", dial = ipc_url)
nanonext::opt(sock, "serial") <- cfg

example_stream <- nanoarrow::example_ipc_stream()
max_attempts <- 20
send_result <- nanonext::send(sock, example_stream, mode = "raw")
attempt <- 1
while (nanonext::is_error_value(send_result) && attempt < max_attempts) {
  Sys.sleep(1)
  send_result <- nanonext::send(sock, example_stream, mode = "raw")
  attempt <- attempt + 1
}
print(send_result)
#> [1] 0
echo_proc$is_alive()
#> [1] TRUE
Sys.sleep(1)
received <- nanonext::recv(sock, mode = "serial")
#> Warning: received data could not be unserialized
attempt <- 1
while (nanonext::is_error_value(received) && attempt < max_attempts) {
  Sys.sleep(1)
  received <- nanonext::recv(sock, mode = "serial")
  attempt <- attempt + 1
}
sent_df <- as.data.frame(read_nanoarrow(example_stream))
received_df <- as.data.frame(read_nanoarrow(received))
print(sent_df)
#>   some_col
#> 1        0
#> 2        1
#> 3        2
print(received_df)
#>   some_col
#> 1        0
#> 2        1
#> 3        2
identical(sent_df, received_df)
#> [1] TRUE
close(sock)
echo_proc$kill()
#> [1] TRUE
```

## LLM Usage Disclosure

Code and documentation in this project have been generated with the
assistance of the github Copilot LLM tools. While we have reviewed and
edited the generated content, we acknowledge that LLM tools were used in
the creation process and accordingly (since these models are trained on
GPL code and other commons + proprietary software license is fake
anyway) the code is released under GPL-3. So if you use this code in any
way, you must comply with the GPL-3 license.
