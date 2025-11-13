library(mangoro)
library(nanonext)
library(nanoarrow)
library(processx)

# Build RPC server
rpc_server_path <- file.path(
  system.file("go", package = "mangoro"),
  "cmd",
  "rpc-example",
  "main.go"
)
rpc_bin <- tempfile()
mangoro_go_build(rpc_server_path, rpc_bin)

# Start server
ipc_url <- create_ipc_path()
rpc_proc <- processx::process$new(
  rpc_bin,
  args = ipc_url,
  stdout = "|",
  stderr = "|"
)
Sys.sleep(2)

cat("Server alive:", rpc_proc$is_alive(), "\n")
cat("Server stdout:", rpc_proc$read_output_lines(), "\n")
cat("Server stderr:", rpc_proc$read_error_lines(), "\n")

if (!rpc_proc$is_alive()) {
  stop("Server failed to start!")
}

# Test matrix transpose
sock <- nanonext::socket("req", dial = ipc_url)

# Create a 3x4 matrix
mat <- matrix(c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12), nrow = 3, ncol = 4)
cat("Input matrix (3x4):\n")
print(mat)

# Convert to data.frame
input_df <- as.data.frame(mat)
colnames(input_df) <- paste0("V", 1:ncol(mat))
cat("\nInput data.frame:\n")
print(input_df)

# Call transpose function
result <- mangoro_rpc_call(sock, "transposeMatrix", input_df)
result_df <- as.data.frame(result)

cat("\nTransposed result (4x3):\n")
print(result_df)

cat("\nR's t(mat) for comparison:\n")
print(t(mat))

cat("\nMatrices match:", all.equal(as.matrix(result_df), t(mat)), "\n")

close(sock)
rpc_proc$kill()
