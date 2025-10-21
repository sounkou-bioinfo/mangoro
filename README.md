
<p align="center">
<img src="inst/docs/logo.svg" alt="mangoro hexsticker" width="180"/>
</p>

[![mangoro status
badge](https://sounkou-bioinfo.r-universe.dev/mangoro/badges/version)](https://sounkou-bioinfo.r-universe.dev/mangoro)

# mangoro

R/Go IPC with Nanomsg Next Gen.

## What is mangoro?

We vendor the [mangos/v3](https://github.com/nanomsg/mangos) and
[arrow-go](https://github.com/apache/arrow-go) Go packages for IPC
between R and Go processes using the `nanonext` R package. The package
provides helper functions to build Go binaries that use mangos and Arrow
for IPC. This is a basic setup that can be used as a starting point for
more complex R/Go IPC applications.

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
#> [1] "/tmp/RtmpQuTRF2/file11378473efccdd"

ipc_url <- create_ipc_path()
ipc_url
#> [1] "ipc:///tmp/RtmpQuTRF2/mangoro-echo1137844ce05e58.sock"
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

## Arrow IPC with nanoarrow, nanonext, and Go binary

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
#> [1] "/tmp/RtmpQuTRF2/file11378433a14331"

echo_proc <- processx::process$new(tmp_bin, args = ipc_url, stdout = "|", stderr = "|"  )
Sys.sleep(3)
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
