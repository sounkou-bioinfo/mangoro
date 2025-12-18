# Start the mangoro HTTP bridge controller (inst/go/cmd/http-bridge/main.go)
# and drive it via RPC. The controller registers RPC methods:
#   - startServer(addr, dir, prefix, cors, coop, tls, cert, key, silent)
#   - stopServer()
#   - serverStatus()
#
# This script:
# 1) Builds the controller binary (or uses MANGORO_HTTP_BIN if provided).
# 2) Starts it on an IPC endpoint chosen by R.
# 3) Calls startServer/status over REQ/REP using mangoro RPC helpers.
# 4) Keeps the controller running until interrupted.

library(mangoro)
library(nanonext)

build_controller <- function(src = NULL, bin_override = NULL) {
  if (
    !is.null(bin_override) && bin_override != "" && file.exists(bin_override)
  ) {
    return(bin_override)
  }
  if (is.null(src) || src == "") {
    local_src <- normalizePath(
      file.path(getwd(), "inst/go/cmd/http-bridge/main.go"),
      mustWork = FALSE
    )
    if (file.exists(local_src)) {
      src <- local_src
    } else {
      src <- system.file("go/cmd/http-bridge/main.go", package = "mangoro")
    }
  }
  if (!file.exists(src)) {
    stop("controller source not found: ", src)
  }
  bin <- tempfile(fileext = if (.Platform$OS.type == "windows") ".exe" else "")
  mangoro_go_build(src, bin, gomaxprocs = 1)
  bin
}

start_controller <- function(bin, ipc_url) {
  if (!requireNamespace("processx", quietly = TRUE)) {
    stop("processx required to launch controller")
  }
  proc <- processx::process$new(
    bin,
    args = ipc_url,
    stdout = "|",
    stderr = "|",
    supervise = TRUE
  )
  Sys.sleep(0.5)
  if (!proc$is_alive()) {
    stop(
      "controller failed\nstdout:\n",
      proc$read_output(),
      "\nstderr:\n",
      proc$read_error()
    )
  }
  proc
}

# Configuration (override via env)
ipc_url <- Sys.getenv(
  "MANGORO_HTTP_IPC",
  sprintf("ipc://%s", file.path(tempdir(), "mangoro-http-control.ipc"))
)
http_addr <- Sys.getenv("MANGORO_HTTP_ADDR", "127.0.0.1:8080")
static_dir <- Sys.getenv("MANGORO_HTTP_DIR", getwd())

controller_bin <- build_controller(
  src = Sys.getenv("MANGORO_HTTP_SRC", ""),
  bin_override = Sys.getenv("MANGORO_HTTP_BIN", "")
)
ctl_proc <- start_controller(controller_bin, ipc_url)
on.exit(
  {
    ctl_proc$kill()
    message("controller stdout:\n", ctl_proc$read_output())
    message("controller stderr:\n", ctl_proc$read_error())
  },
  add = TRUE
)

ctl_sock <- nanonext::socket("req", dial = ipc_url)
on.exit(close(ctl_sock), add = TRUE)

message("Controller manifest:")
print(mangoro_rpc_get_manifest(ctl_sock))

message("Starting HTTP server at http://", http_addr, " serving ", static_dir)
start_df <- data.frame(
  addr = http_addr,
  dir = static_dir,
  prefix = "/",
  cors = FALSE,
  coop = FALSE,
  tls = FALSE,
  cert = "",
  key = "",
  silent = FALSE,
  stringsAsFactors = FALSE
)
start_res <- mangoro_rpc_call(ctl_sock, "startServer", start_df)
message("startServer result:")
print(nanoarrow::as_data_frame(start_res))

status_res <- mangoro_rpc_call(
  ctl_sock,
  "serverStatus",
  data.frame(dummy = integer(0))
)
message("serverStatus result:")
print(nanoarrow::as_data_frame(status_res))

hold_secs <- as.numeric(Sys.getenv("MANGORO_HTTP_HOLD", "5"))
message("Server running for ", hold_secs, "s (override with MANGORO_HTTP_HOLD).")
Sys.sleep(hold_secs)

stop_res <- mangoro_rpc_call(
  ctl_sock,
  "stopServer",
  data.frame(dummy = integer(0))
)
message("stopServer result:")
print(nanoarrow::as_data_frame(stop_res))
