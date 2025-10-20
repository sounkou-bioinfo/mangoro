
R/Go IPC with Nanomsg Next Gen

## Test echo server setup

``` r
library(mangoro)
library(nanonext)
library(processx)

# Create a unique IPC path for the test
tmp_ipc <- tempfile(pattern = "mangoro-echo", fileext = ".ipc")
if (.Platform$OS.type == "windows") {
  ipc_url <- paste0("ipc://", gsub("/", "\\\\", tmp_ipc))
} else {
  ipc_url <- paste0("ipc://", tmp_ipc)
}

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
