library(mangoro)
library(nanonext)
library(processx)

# vendored mangos version
get_mangos_version()
go_echo_code <- paste(
    "package main",
    "import (",
    '  "os"',
    '  "go.nanomsg.org/mangos/v3/protocol/rep"',
    '  _ "go.nanomsg.org/mangos/v3/transport/ipc"',
    ")",
    "func main() {",
    "  url := os.Args[1]",
    "  sock, _ := rep.NewSocket()",
    "  sock.Listen(url)",
    "  for {",
    "    msg, _ := sock.Recv()",
    '    newMsg := append(msg, []byte(" [echoed by Go]")...)',
    "    sock.Send(newMsg)",
    "  }",
    "}",
    sep = "\n"
)

tmp_go <- tempfile(fileext = ".go")
writeLines(go_echo_code, tmp_go)

tmp_bin <- if (.Platform$OS.type == "windows") {
    tempfile(fileext = ".exe")
} else {
    tempfile()
}
mangoro_go_build(tmp_go, tmp_bin)

ipc_url <- create_ipc_path()
ipc_url
echo_proc <- processx::process$new(tmp_bin, args = ipc_url)
on.exit(echo_proc$kill())
Sys.sleep(3)
sock <- nanonext::socket("req", dial = ipc_url)
msg <- charToRaw("hello from R")
send_result <- nanonext::send(sock, msg, mode = "raw")
# Retry send up to 5 times if error
max_attempts <- 15
attempt <- 1
while (nanonext::is_error_value(send_result) && attempt < max_attempts) {
    Sys.sleep(1)
    send_result <- nanonext::send(sock, msg, mode = "raw")
    attempt <- attempt + 1
}
print(send_result)
# Retry recv up to 5 times if error
rep <- nanonext::recv(sock, mode = "raw")
attempt <- 15
while (nanonext::is_error_value(rep) && attempt < max_attempts) {
    Sys.sleep(1)
    rep <- nanonext::recv(sock, mode = "raw")
    attempt <- attempt + 1
}
Sys.sleep(3)
print(rawToChar(rep))
close(sock)
