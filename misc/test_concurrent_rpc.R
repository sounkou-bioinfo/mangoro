library(mangoro)
library(nanonext)
library(nanoarrow)
library(processx)
library(parallel)

# Build and start RPC server
rpc_server_path <- file.path(
    system.file("go", package = "mangoro"),
    "cmd",
    "rpc-example",
    "main.go"
)
rpc_bin <- tempfile()
mangoro_go_build(rpc_server_path, rpc_bin)

ipc_url <- create_ipc_path()
rpc_proc <- processx::process$new(
    rpc_bin,
    args = ipc_url,
    stdout = "|",
    stderr = "|"
)
Sys.sleep(2)

cat("Server alive:", rpc_proc$is_alive(), "\n")
cat("Server output:", rpc_proc$read_output_lines(), "\n\n")

# Function to call add RPC in parallel
test_add_concurrent <- function(client_id, ipc_url) {
    # Create socket INSIDE the forked process
    sock <- nanonext::socket("req", dial = ipc_url)

    # Add some delay to ensure concurrent requests
    Sys.sleep(runif(1, 0, 0.1))

    # Create unique input for this client
    x_val <- client_id * 10
    input_df <- data.frame(
        x = c(x_val, x_val + 1, x_val + 2),
        y = c(1, 2, 3)
    )

    cat(sprintf("Client %d: Sending request at %s\n", client_id, Sys.time()))
    start_time <- Sys.time()

    result <- mangoro_rpc_call(sock, "add", input_df)
    result_df <- as.data.frame(result)

    end_time <- Sys.time()
    elapsed <- as.numeric(end_time - start_time, units = "secs")

    close(sock)

    cat(sprintf(
        "Client %d: Got result at %s (%.3f sec)\n",
        client_id,
        Sys.time(),
        elapsed
    ))

    list(
        client_id = client_id,
        input = input_df,
        result = result_df,
        elapsed = elapsed
    )
}

# Function to call transpose RPC in parallel
test_transpose_concurrent <- function(client_id, ipc_url) {
    # Create socket INSIDE the forked process
    sock <- nanonext::socket("req", dial = ipc_url)

    Sys.sleep(runif(1, 0, 0.1))

    # Create unique matrix for this client - use numeric (float64)
    mat <- matrix(as.numeric(client_id:(client_id + 11)), nrow = 3, ncol = 4)
    input_df <- as.data.frame(mat)
    for (j in seq_along(input_df)) input_df[[j]] <- as.numeric(input_df[[j]])
    colnames(input_df) <- paste0("V", seq_len(ncol(mat)))

    cat(sprintf(
        "Client %d: Sending transpose request at %s\n",
        client_id,
        Sys.time()
    ))
    start_time <- Sys.time()

    result <- mangoro_rpc_call(sock, "transposeMatrix", input_df)
    result_df <- as.data.frame(result)

    end_time <- Sys.time()
    elapsed <- as.numeric(end_time - start_time, units = "secs")

    close(sock)

    cat(sprintf(
        "Client %d: Got transpose result at %s (%.3f sec)\n",
        client_id,
        Sys.time(),
        elapsed
    ))

    list(
        client_id = client_id,
        input = input_df,
        result = result_df,
        elapsed = elapsed
    )
}

cat("=== Test 1: Concurrent ADD calls ===\n")
n_clients <- 5
start_time <- Sys.time()

# Use PSOCK cluster for true parallelism (works on all platforms)
# Each worker is a separate R process - no fork issues
cl <- makeCluster(n_clients)
clusterExport(cl, c("ipc_url"), envir = environment())
clusterEvalQ(cl, {
    library(mangoro)
    library(nanonext)
    library(nanoarrow)
})

results_add <- parLapply(
    cl,
    1:n_clients,
    test_add_concurrent,
    ipc_url = ipc_url
)
stopCluster(cl)

total_time_add <- as.numeric(Sys.time() - start_time, units = "secs")
cat(sprintf(
    "\nTotal time for %d ADD calls: %.3f sec\n",
    n_clients,
    total_time_add
))
cat(sprintf(
    "Average time per call: %.3f sec\n",
    mean(sapply(results_add, function(x) x$elapsed))
))

# Verify results
cat("\nVerifying ADD results:\n")
for (i in seq_along(results_add)) {
    r <- results_add[[i]]
    expected <- r$input$x + r$input$y
    actual <- r$result$result
    match <- all.equal(expected, actual)
    cat(sprintf(
        "Client %d: %s\n",
        r$client_id,
        ifelse(isTRUE(match), "PASS", "FAIL")
    ))
}

cat("\n=== Test 2: Concurrent TRANSPOSE calls ===\n")
start_time <- Sys.time()

cl <- makeCluster(n_clients)
clusterExport(cl, c("ipc_url"), envir = environment())
clusterEvalQ(cl, {
    library(mangoro)
    library(nanonext)
    library(nanoarrow)
})

results_transpose <- parLapply(
    cl,
    1:n_clients,
    test_transpose_concurrent,
    ipc_url = ipc_url
)
stopCluster(cl)

total_time_transpose <- as.numeric(Sys.time() - start_time, units = "secs")
cat(sprintf(
    "\nTotal time for %d TRANSPOSE calls: %.3f sec\n",
    n_clients,
    total_time_transpose
))
cat(sprintf(
    "Average time per call: %.3f sec\n",
    mean(sapply(results_transpose, function(x) x$elapsed))
))

# Verify transpose results
cat("\nVerifying TRANSPOSE results:\n")
for (i in seq_along(results_transpose)) {
    r <- results_transpose[[i]]
    input_mat <- as.matrix(r$input)
    result_mat <- as.matrix(r$result)
    expected <- t(input_mat)
    match <- all.equal(result_mat, expected, check.attributes = FALSE)
    cat(sprintf(
        "Client %d: %s\n",
        r$client_id,
        ifelse(isTRUE(match), "PASS", "FAIL")
    ))
}

cat("\n=== Summary ===\n")
cat(sprintf(
    "Concurrent processing: YES (PSOCK cluster - %d workers)\n",
    n_clients
))
cat(sprintf(
    "All ADD results correct: %s\n",
    ifelse(
        all(sapply(results_add, function(r) {
            isTRUE(all.equal(r$input$x + r$input$y, r$result$result))
        })),
        "YES",
        "NO"
    )
))
cat(sprintf(
    "All TRANSPOSE results correct: %s\n",
    ifelse(
        all(sapply(results_transpose, function(r) {
            isTRUE(all.equal(
                as.matrix(r$result),
                t(as.matrix(r$input)),
                check.attributes = FALSE
            ))
        })),
        "YES",
        "NO"
    )
))

rpc_proc$kill()
cat("\nServer stopped.\n")
