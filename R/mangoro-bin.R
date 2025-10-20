#' Find the path to a mangoro Go binary
#'
#' @param name Name of the binary (e.g. "echo")
#' @return Full path to the binary in the installed package
#' @export
find_mangoro_bin <- function(name) {
    bin_dir <- system.file("bin", package = "mangoro")
    if (.Platform$OS.type == "windows") {
        name <- paste0(name, ".exe")
    }
    path <- file.path(bin_dir, name)
    if (!file.exists(path)) {
        stop(sprintf("Binary '%s' not found at '%s'", name, path))
    }
    path
}

#' Run a mangoro Go binary with arguments
#'
#' @param name Name of the binary (e.g. "echo")
#' @param args Arguments to pass to the binary
#' @param ... Additional arguments passed to processx::process$new
#' @return A processx process object
#' @export
run_mangoro_bin <- function(name, args = character(), ...) {
    bin <- find_mangoro_bin(name)
    processx::process$new(bin, args = args, ...)
}

#' Generate a platform-correct IPC URL for mangoro
#'
#' @param prefix Prefix for the temp file (default: "mangoro-echo")
#' @return IPC URL string suitable for nanonext and mangoro Go binaries
#' @export
mangoro_ipc_url <- function(prefix = "mangoro-echo") {
    tmp_ipc <- tempfile(pattern = prefix, fileext = ".ipc")
    if (.Platform$OS.type == "windows") {
        ipc_url <- paste0("ipc://", gsub("/", "\\\\", tmp_ipc))
    } else {
        ipc_url <- paste0("ipc://", tmp_ipc)
    }
    ipc_url
}
