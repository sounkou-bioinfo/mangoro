#' @import nanonext
#' @import nanoarrow
NULL

#' find_mangoro_bin
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
mangoro_ipc_url <- create_ipc_path

#' Create a unique IPC path for mangoro
#'
#' @param prefix Prefix for the temp file (default: "mangoro-echo")
#' @return IPC URL string suitable for nanonext and mangoro Go binaries
#' @export
create_ipc_path <- function(prefix = "mangoro-echo") {
  tmp_ipc <- tempfile(pattern = prefix, fileext = ".socket")
  tmp_ipc <- normalizePath(tmp_ipc, mustWork = FALSE)
  if (.Platform$OS.type == "windows") {
    ipc_url <- paste0("ipc://", gsub("/", "\\\\", tmp_ipc))
  } else {
    ipc_url <- paste0("ipc://", tmp_ipc)
  }
  ipc_url
}

#' Find the path to the Go executable
#'
#' @return Path to the Go binary
#' @export
find_go <- function() {
  go <- Sys.which("go")
  if (!nzchar(go)) {
    stop("Go not found in PATH")
  }
  go
}

#' Find the path to the mangoro vendor directory
#'
#' @return Path to the vendor directory (inst/go/vendor)
#' @export
find_mangoro_vendor <- function() {
  vend <- system.file("go/vendor", package = "mangoro")
  if (!dir.exists(vend)) {
    stop("Vendor directory not found: ", vend)
  }
  vend
}

#' Compile a Go source file using the vendored dependencies
#'
#' @param src Path to the Go source file
#' @param out Path to the output binary
#' @param ... Additional arguments to pass to Go build
#' @return Path to the compiled binary
#' @export
mangoro_go_build <- function(src, out, ...) {
  go <- find_go()
  vend <- dirname(find_mangoro_vendor())
  cmd <- sprintf('"%s" build -mod=vendor -o "%s" "%s"', go, out, src)
  oldwd <- setwd(vend)
  on.exit(setwd(oldwd))
  status <- system(cmd, intern = TRUE, ...)
  if (!file.exists(out)) {
    print(status)
    stop("Go build failed")
  }
  out
}

#' Get the version of vendored mangos using Go tooling (no jsonlite)
#'
#' @return The version string of go.nanomsg.org/mangos/v3 in the vendor go.mod
#' @export
get_mangos_version <- function() {
  go <- find_go()
  vend <- dirname(find_mangoro_vendor())
  oldwd <- setwd(vend)
  on.exit(setwd(oldwd))
  res <- suppressWarnings(
    system2(
      go,
      c("list", "-m", "go.nanomsg.org/mangos/v3"),
      stdout = TRUE,
      stderr = TRUE
    )
  )
  if (
    length(res) == 0 ||
      any(grepl(
        "not a module|no required module",
        res,
        ignore.case = TRUE
      ))
  ) {
    return(NA_character_)
  }
  # Output is like: "go.nanomsg.org/mangos/v3 v3.2.2"
  version <- sub(
    "^go\\.nanomsg\\.org/mangos/v3\\s+",
    "",
    grep("^go\\.nanomsg\\.org/mangos/v3", res, value = TRUE)
  )
  if (length(version) == 0) {
    return(NA_character_)
  }
  version
}

#' Get the version of vendored Arrow Go using Go tooling (no jsonlite)
#'
#' @return The version string of github.com/apache/arrow/go/v18 in the vendor go.mod
#' @export
get_arrow_go_version <- function() {
  go <- find_go()
  vend <- dirname(find_mangoro_vendor())
  oldwd <- setwd(vend)
  on.exit(setwd(oldwd))
  res <- suppressWarnings(
    system2(
      go,
      c("list", "-m", "github.com/apache/arrow/go/v18"),
      stdout = TRUE,
      stderr = TRUE
    )
  )
  if (
    length(res) == 0 ||
      any(grepl(
        "not a module|no required module",
        res,
        ignore.case = TRUE
      ))
  ) {
    return(NA_character_)
  }
  # Output is like: "github.com/apache/arrow/go/v18 v18.0.0"
  version <- sub(
    "^github\\.com/apache/arrow/go/v18\\s+",
    "",
    grep("^github\\.com/apache/arrow/go/v18", res, value = TRUE)
  )
  if (length(version) == 0) {
    return(NA_character_)
  }
  version
}
