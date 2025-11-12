#' Pack a 32-bit integer to raw bytes (big-endian)
#'
#' @param x An integer value
#' @return A raw vector of length 4
#' @export
pack_int32 <- function(x) {
    as.raw(c(
        (x %/% 16777216) %% 256,
        (x %/% 65536) %% 256,
        (x %/% 256) %% 256,
        x %% 256
    ))
}

#' Unpack a 32-bit integer from raw bytes (big-endian)
#'
#' @param bytes A raw vector of length 4
#' @return An integer value
#' @export
unpack_int32 <- function(bytes) {
    val <- as.numeric(bytes[1]) * 16777216 + as.numeric(bytes[2]) * 65536 +
        as.numeric(bytes[3]) * 256 + as.numeric(bytes[4])
    as.integer(val)
}

#' Create an RPC manifest request message
#'
#' @return A raw vector containing the manifest request
#' @export
rpc_manifest_request <- function() {
    c(as.raw(0), pack_int32(0), pack_int32(0))
}

#' Create an RPC function call message
#'
#' @param func_name Name of the function to call
#' @param data Data frame or Arrow stream to send as arguments
#' @return A raw vector containing the RPC call message
#' @export
rpc_call_message <- function(func_name, data) {
    tmp_arrow <- rawConnection(raw(0), "wb")
    nanoarrow::write_nanoarrow(data, tmp_arrow)
    arrow_bytes <- rawConnectionValue(tmp_arrow)
    close(tmp_arrow)

    name_bytes <- charToRaw(func_name)
    name_len <- length(name_bytes)

    c(
        as.raw(1),
        pack_int32(name_len),
        name_bytes,
        pack_int32(0),
        arrow_bytes
    )
}

#' Parse an RPC response message
#'
#' @param response Raw vector containing the RPC response
#' @return A list with components: type, func_name, error_msg, data
#' @export
rpc_parse_response <- function(response) {
    msg_type <- as.integer(response[1])
    name_len <- unpack_int32(response[2:5])

    func_name <- ""
    if (name_len > 0) {
        func_name <- rawToChar(response[6:(5 + name_len)])
    }

    error_start <- 6L + as.integer(name_len)
    error_len <- unpack_int32(response[error_start:(error_start + 3L)])

    error_msg <- ""
    if (error_len > 0) {
        error_msg <- rawToChar(response[(error_start + 4L):(error_start + 3L + error_len)])
    }

    data_start <- error_start + 4L + as.integer(error_len)
    data_bytes <- response[data_start:length(response)]

    list(
        type = msg_type,
        func_name = func_name,
        error_msg = error_msg,
        data = data_bytes
    )
}

#' Send a message with retries
#'
#' @param sock A nanonext socket
#' @param msg Message to send (raw vector)
#' @param max_attempts Maximum number of retry attempts (default 20)
#' @return The result from nanonext::send
#' @export
rpc_send <- function(sock, msg, max_attempts = 20) {
    send_result <- nanonext::send(sock, msg, mode = "raw")
    attempt <- 1
    while (nanonext::is_error_value(send_result) && attempt < max_attempts) {
        Sys.sleep(1)
        send_result <- nanonext::send(sock, msg, mode = "raw")
        attempt <- attempt + 1
    }
    send_result
}

#' Receive a message with retries
#'
#' @param sock A nanonext socket
#' @param max_attempts Maximum number of retry attempts (default 20)
#' @return The received message as a raw vector
#' @export
rpc_recv <- function(sock, max_attempts = 20) {
    response <- nanonext::recv(sock, mode = "raw")
    attempt <- 1
    while (nanonext::is_error_value(response) && attempt < max_attempts) {
        Sys.sleep(1)
        response <- nanonext::recv(sock, mode = "raw")
        attempt <- attempt + 1
    }
    response
}

#' Get the manifest of registered functions from an RPC server
#'
#' @param sock A nanonext socket connected to the RPC server
#' @return A list of function signatures
#' @export
rpc_get_manifest <- function(sock) {
    msg <- rpc_manifest_request()
    rpc_send(sock, msg)
    response <- rpc_recv(sock)
    parsed <- rpc_parse_response(response)

    if (parsed$type == 3) {
        stop("RPC error: ", parsed$error_msg)
    }

    jsonlite::fromJSON(rawToChar(parsed$data))
}

#' Call a remote function via RPC
#'
#' @param sock A nanonext socket connected to the RPC server
#' @param func_name Name of the function to call
#' @param data Data frame or Arrow stream to send as arguments
#' @return A data frame with the result
#' @export
rpc_call <- function(sock, func_name, data) {
    msg <- rpc_call_message(func_name, data)
    rpc_send(sock, msg)
    response <- rpc_recv(sock)
    parsed <- rpc_parse_response(response)

    if (parsed$type == 3) {
        stop("RPC error: ", parsed$error_msg)
    }

    as.data.frame(nanoarrow::read_nanoarrow(parsed$data))
}
