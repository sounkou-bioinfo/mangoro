
[![mangoro status
badge](https://sounkou-bioinfo.r-universe.dev/mangoro/badges/version)](https://sounkou-bioinfo.r-universe.dev/mangoro)

# mangoro

R/Go IPC with Nanomsg Next Gen.

<p>
<img src="inst/docs/logo.svg" alt="" width="180" align="right"/>
</p>

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
#> [1] "GOMAXPROCS=1 /usr/lib/go-1.22/bin/go 'build' '-mod=vendor' '-o' '/tmp/RtmpWdO81v/file16576f6f91b78b' '/tmp/RtmpWdO81v/file16576f51958f24.go'"
#> [1] "/tmp/RtmpWdO81v/file16576f6f91b78b"
```

create IPC path and send/receive message

``` r
ipc_url <- create_ipc_path()
echo_proc <- processx::process$new(tmp_bin, args = ipc_url)
Sys.sleep(1)
echo_proc$is_alive()
#> [1] TRUE
sock <- nanonext::socket("req", dial = ipc_url)
msg <- charToRaw("hello from R")

max_attempts <- 20
send_result <- nanonext::send(sock, msg, mode = "raw")
attempt <- 1
while (nanonext::is_error_value(send_result) && attempt < max_attempts) {
  Sys.sleep(1)
  send_result <- nanonext::send(sock, msg, mode = "raw")
  attempt <- attempt + 1
}

response <- nanonext::recv(sock, mode = "raw")
attempt <- 1
while (nanonext::is_error_value(response) && attempt < max_attempts) {
  Sys.sleep(1)
  response <- nanonext::recv(sock, mode = "raw")
  attempt <- attempt + 1
}

rawToChar(response)
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
#> [1] "GOMAXPROCS=1 /usr/lib/go-1.22/bin/go 'build' '-mod=vendor' '-o' '/tmp/RtmpWdO81v/file16576f58ef9e17' '/tmp/RtmpWdO81v/file16576f5a3ffc.go'"
#> [1] "/tmp/RtmpWdO81v/file16576f58ef9e17"

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

## RPC with Function Registration

The package includes `rgoipc`, a Go package for building RPC servers
with function registration.

``` r
library(nanoarrow)

rpc_server_path <- file.path(system.file("go", package = "mangoro"), "cmd", "rpc-example", "main.go")
rpc_bin <- tempfile()
mangoro_go_build(rpc_server_path, rpc_bin)
#> [1] "GOMAXPROCS=1 /usr/lib/go-1.22/bin/go 'build' '-mod=vendor' '-o' '/tmp/RtmpWdO81v/file16576f245aa049' '/usr/local/lib/R/site-library/mangoro/go/cmd/rpc-example/main.go'"
#> [1] "/tmp/RtmpWdO81v/file16576f245aa049"

ipc_url <- create_ipc_path()
rpc_proc <- processx::process$new(rpc_bin, args = ipc_url, stdout = "|", stderr = "|")
Sys.sleep(2)
rpc_proc$is_alive()
#> [1] TRUE
```

Request the manifest of registered functions:

``` r
sock <- nanonext::socket("req", dial = ipc_url)

packInt32 <- function(x) {
  as.raw(c((x %/% 16777216) %% 256, (x %/% 65536) %% 256, (x %/% 256) %% 256, x %% 256))
}

unpackInt32 <- function(bytes) {
  val <- as.numeric(bytes[1]) * 16777216 + as.numeric(bytes[2]) * 65536 + 
    as.numeric(bytes[3]) * 256 + as.numeric(bytes[4])
  as.integer(val)
}

manifest_msg <- c(as.raw(0), packInt32(0), packInt32(0))
max_attempts <- 20
send_result <- nanonext::send(sock, manifest_msg, mode = "raw")
attempt <- 1
while (nanonext::is_error_value(send_result) && attempt < max_attempts) {
  Sys.sleep(1)
  send_result <- nanonext::send(sock, manifest_msg, mode = "raw")
  attempt <- attempt + 1
}

manifest_response <- nanonext::recv(sock, mode = "raw")
attempt <- 1
while (nanonext::is_error_value(manifest_response) && attempt < max_attempts) {
  Sys.sleep(1)
  manifest_response <- nanonext::recv(sock, mode = "raw")
  attempt <- attempt + 1
}

msg_type <- as.integer(manifest_response[1])
name_len <- unpackInt32(manifest_response[2:5])
error_start <- 6L + as.integer(name_len)
error_len <- unpackInt32(manifest_response[error_start:(error_start+3L)])
json_start <- error_start + 4L + as.integer(error_len)
manifest_json <- rawToChar(manifest_response[json_start:length(manifest_response)])
manifest <- jsonlite::fromJSON(manifest_json)
print(manifest)
#> $add
#> $add$Args
#>   Name Type.Type Type.Nullable Type.StructDef Type.ListSchema Optional Default
#> 1    x   float64          TRUE             NA              NA    FALSE      NA
#> 2    y   float64          TRUE             NA              NA    FALSE      NA
#> 
#> $add$ReturnType
#> $add$ReturnType$Type
#> [1] "float64"
#> 
#> $add$ReturnType$Nullable
#> [1] TRUE
#> 
#> $add$ReturnType$StructDef
#> NULL
#> 
#> $add$ReturnType$ListSchema
#> NULL
#> 
#> 
#> $add$Vectorized
#> [1] TRUE
#> 
#> $add$Metadata
#> $add$Metadata$description
#> [1] "Add two numeric vectors"

close(sock)
```

Call the `add` function with Arrow IPC data:

``` r
sock <- nanonext::socket("req", dial = ipc_url)

input_df <- data.frame(x = c(1.5, 2.5, 3.5, NA), y = c(0.5, 1.5, 2.5, 4.5))
tmp_arrow <- rawConnection(raw(0), "wb")
nanoarrow::write_nanoarrow(input_df, tmp_arrow)
arrow_bytes <- rawConnectionValue(tmp_arrow)
close(tmp_arrow)

func_name <- "add"
name_bytes <- charToRaw(func_name)
name_len <- length(name_bytes)

call_msg <- c(
  as.raw(1),
  packInt32(name_len),
  name_bytes,
  packInt32(0),
  arrow_bytes
)

send_result <- nanonext::send(sock, call_msg, mode = "raw")
attempt <- 1
while (nanonext::is_error_value(send_result) && attempt < max_attempts) {
  Sys.sleep(1)
  send_result <- nanonext::send(sock, call_msg, mode = "raw")
  attempt <- attempt + 1
}

call_response <- nanonext::recv(sock, mode = "raw")
attempt <- 1
while (nanonext::is_error_value(call_response) && attempt < max_attempts) {
  Sys.sleep(1)
  call_response <- nanonext::recv(sock, mode = "raw")
  attempt <- attempt + 1
}

resp_type <- as.integer(call_response[1])
resp_name_len <- unpackInt32(call_response[2:5])
resp_error_start <- 6L + as.integer(resp_name_len)
resp_error_len <- unpackInt32(call_response[resp_error_start:(resp_error_start+3L)])

if (resp_type == 3) {
  error_msg <- rawToChar(call_response[(resp_error_start+4L):(resp_error_start+3L+resp_error_len)])
  stop("RPC error: ", error_msg)
}

resp_arrow_start <- resp_error_start + 4L + as.integer(resp_error_len)
result_bytes <- call_response[resp_arrow_start:length(call_response)]
result_df <- as.data.frame(nanoarrow::read_nanoarrow(result_bytes))

print(input_df)
#>     x   y
#> 1 1.5 0.5
#> 2 2.5 1.5
#> 3 3.5 2.5
#> 4  NA 4.5
print(result_df)
#>   result
#> 1      2
#> 2      4
#> 3      6
#> 4     NA
print(input_df$x + input_df$y)
#> [1]  2  4  6 NA

close(sock)
rpc_proc$kill()
#> [1] TRUE
```

The `rgoipc` package provides interfaces for type-safe function
registration with Arrow schema validation. See
[inst/go/pkg/rgoipc](inst/go/pkg/rgoipc) for the Go package and
[inst/go/cmd/rpc-example](inst/go/cmd/rpc-example) for a complete server
example.

## LLM Usage Disclosure

Code and documentation in this project have been generated with the
assistance of the github Copilot LLM tools. While we have reviewed and
edited the generated content, we acknowledge that LLM tools were used in
the creation process and accordingly (since these models are trained on
GPL code and other commons + proprietary software license is fake
anyway) the code is released under GPL-3. So if you use this code in any
way, you must comply with the GPL-3 license.
