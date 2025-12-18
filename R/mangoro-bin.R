#' @import nanonext
#' @import nanoarrow
#' @import jsonlite
NULL

# Internal helper to run code with isolated Go environment
# Temporarily sets HOME, GOCACHE, and GOENV to temp locations
with_isolated_go_env <- function(expr) {
  # Save original environment

  old_home <- Sys.getenv("HOME", unset = NA)
  old_gocache <- Sys.getenv("GOCACHE", unset = NA)

  old_goenv <- Sys.getenv("GOENV", unset = NA)

  # Create temp HOME
  temp_home <- tempfile(pattern = "gohome")
  dir.create(temp_home, showWarnings = FALSE)

  # Set isolated environment
  Sys.setenv(HOME = temp_home)
  Sys.setenv(GOCACHE = tempdir())
  Sys.setenv(GOENV = tempfile(pattern = "goenv", fileext = ".env"))

  # Restore on exit
  on.exit(
    {
      if (is.na(old_home)) {
        Sys.unsetenv("HOME")
      } else {
        Sys.setenv(HOME = old_home)
      }
      if (is.na(old_gocache)) {
        Sys.unsetenv("GOCACHE")
      } else {
        Sys.setenv(GOCACHE = old_gocache)
      }
      if (is.na(old_goenv)) {
        Sys.unsetenv("GOENV")
      } else {
        Sys.setenv(GOENV = old_goenv)
      }
      unlink(temp_home, recursive = TRUE, force = TRUE)
    },
    add = TRUE
  )

  # Evaluate expression
  force(expr)
}


#' Create a unique IPC path for mangoro
#'
#' @param prefix Prefix for the temp file (default: "mangoro-echo")
#' @return IPC URL string suitable for nanonext and mangoro Go binaries
#' @export
create_ipc_path <- function(prefix = "mangoro-echo") {
  tmp_ipc <- tempfile(pattern = prefix, fileext = ".ipc")
  if (.Platform$OS.type == "windows") {
    ipc_url <- paste0("ipc://", gsub("/", "\\\\", tmp_ipc))
  } else {
    tmp_ipc <- gsub("/+", "/", x = tmp_ipc)
    ipc_url <- paste0("ipc://", tmp_ipc)
  }
  ipc_url
}

#' Find the path to the Go executable
#'
#' @description
#' Locates a usable `go` binary for runtime IPC helpers. Resolution order:
#' \enumerate{
#'   \item `options(mangoro.go_path)`
#'   \item `Sys.getenv("MANGORO_GO")`
#'   \item `Sys.which("go")`
#' }
#' Candidates are validated by running `go version`. Errors reference the
#' detected OS/arch using user-friendly labels (e.g., macOS arm64).
#'
#' @return Path to the Go binary
#' @export
find_go <- function() {
  opt_go <- getOption("mangoro.go_path", default = "")
  env_go <- Sys.getenv("MANGORO_GO", unset = "")
  candidates <- unique(c(opt_go, env_go, Sys.which("go")))
  candidates <- candidates[nzchar(candidates)]

  for (cand in candidates) {
    go_path <- normalizePath(cand, mustWork = FALSE)
    if (!file.exists(go_path) || file.access(go_path, 1) != 0) {
      next
    }
    version_out <- try(
      system2(go_path, "version", stdout = TRUE, stderr = TRUE),
      silent = TRUE
    )
    if (!inherits(version_out, "try-error")) return(go_path)
  }

  platform <- Sys.info()
  os_label <- switch(
    tolower(platform[["sysname"]]),
    darwin = "macOS",
    windows = "Windows",
    linux = "Linux",
    platform[["sysname"]]
  )
  arch_label <- switch(
    tolower(platform[["machine"]]),
    aarch64 = "arm64",
    platform[["machine"]]
  )
  stop(
    "Go executable not found. Set options(mangoro.go_path=\"/full/path/to/go\") or MANGORO_GO env var, ",
    "or add Go to PATH. Detected platform: ",
    os_label,
    " ",
    arch_label
  )
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
#' @description
#' Compiles a Go source file using the vendored dependencies from the mangoro package.
#'
#' To comply with CRAN policy, this function temporarily redirects several environment
#' variables to prevent Go from writing to user directories:
#' \itemize{
#'   \item \code{HOME} is set to a temporary directory because Go's telemetry system
#'         (introduced in Go 1.23+) writes data to \code{~/.config/go/telemetry}
#'         using \code{os.UserConfigDir()}, which cannot be disabled via environment
#'         variables alone.
#'   \item \code{GOCACHE} is set to a temporary directory to prevent build cache
#'         writes to \code{~/.cache/go-build}.
#'   \item \code{GOENV} is set to a temporary file to prevent config writes to
#'         \code{~/.config/go/env}.
#' }
#' All environment variables are restored and temporary directories cleaned up
#' after the build completes.
#'
#' @param src Path to the Go source file
#' @param out Path to the output binary
#' @param gomaxprocs Number of threads for Go build (sets GOMAXPROCS env variable)
#' @param gocache Path to Go build cache directory. If NULL (default), uses a
#'   temporary directory to comply with CRAN policy. Set to NA to use the default
#'   Go cache location.
#' @param ... Additional arguments to pass to Go build
#' @return Path to the compiled binary
#' @seealso \url{https://go.dev/doc/telemetry} for Go telemetry documentation
#' @export
mangoro_go_build <- function(src, out, gomaxprocs = 1, gocache = NULL, ...) {
  go <- find_go()
  vend <- dirname(find_mangoro_vendor())

  # CRAN compliance: Redirect all Go-related directories to temp locations

  # to prevent writes to user config directories (e.g., ~/.config/go)

  # Save and set HOME to a temporary directory
  # This is necessary because Go's telemetry uses os.UserConfigDir() directly
  # and ignores GOENV for telemetry data storage
  old_home <- Sys.getenv("HOME", unset = NA)
  temp_home <- tempfile(pattern = "gohome")
  dir.create(temp_home, showWarnings = FALSE)
  Sys.setenv(HOME = temp_home)

  # Save and set GOCACHE
  old_gocache <- Sys.getenv("GOCACHE", unset = NA)
  if (is.null(gocache)) {
    Sys.setenv(GOCACHE = tempdir())
  } else if (!is.na(gocache)) {
    Sys.setenv(GOCACHE = gocache)
  }
  # If gocache = NA, leave GOCACHE unchanged

  # Save and set GOENV to a temporary file
  old_goenv <- Sys.getenv("GOENV", unset = NA)
  Sys.setenv(GOENV = tempfile(pattern = "goenv", fileext = ".env"))

  # Restore original environment variables on exit
  on.exit(
    {
      # Restore HOME first
      if (is.na(old_home)) {
        Sys.unsetenv("HOME")
      } else {
        Sys.setenv(HOME = old_home)
      }
      # Clean up temp home directory
      unlink(temp_home, recursive = TRUE, force = TRUE)

      # Restore GOCACHE
      if (!is.null(gocache) || is.na(old_gocache)) {
        if (is.na(old_gocache)) {
          Sys.unsetenv("GOCACHE")
        } else {
          Sys.setenv(GOCACHE = old_gocache)
        }
      }
      # Restore GOENV
      if (is.na(old_goenv)) {
        Sys.unsetenv("GOENV")
      } else {
        Sys.setenv(GOENV = old_goenv)
      }
    },
    add = TRUE
  )

  # Only one -mod flag can be used per go build invocation
  args <- c("build", "-mod=vendor", "-o", out, src)
  oldwd <- setwd(vend)
  on.exit(setwd(oldwd), add = TRUE)
  env <- character()
  if (!is.null(gomaxprocs)) {
    env <- c(sprintf("GOMAXPROCS=%s", as.integer(gomaxprocs)))
    go <- normalizePath(go)
    if (!.Platform$OS.type == "windows") go <- sprintf("%s %s", env, go)
  }
  cmd <- sprintf("%s %s", go, paste(shQuote(args), collapse = " "))
  message(cmd)
  status <- system(
    cmd,
    ignore.stdout = FALSE,
    ignore.stderr = FALSE,
    intern = TRUE,
    ...
  )
  if (!file.exists(out)) {
    message(paste(status, collapse = "\n"))
    stop("Go build failed")
  }
  out
}

#' Get the version of vendored mangos using Go tooling (no jsonlite)
#'
#' @return The version string of go.nanomsg.org/mangos/v3 in the vendor go.mod
#' @export
get_mangos_version <- function() {
  with_isolated_go_env({
    go <- find_go()
    vend <- dirname(find_mangoro_vendor())
    oldwd <- setwd(vend)
    on.exit(setwd(oldwd))
    res <- system2(
      go,
      c("list", "-m", "go.nanomsg.org/mangos/v3"),
      stdout = TRUE,
      stderr = TRUE
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
  })
}

#' Get the version of vendored Arrow Go using Go tooling (no jsonlite)
#'
#' @return The version string of github.com/apache/arrow/go/v18 in the vendor go.mod
#' @export
get_arrow_go_version <- function() {
  with_isolated_go_env({
    go <- find_go()
    vend <- dirname(find_mangoro_vendor())
    oldwd <- setwd(vend)
    on.exit(setwd(oldwd))
    res <- system2(
      go,
      c("list", "-m", "github.com/apache/arrow/go/v18"),
      stdout = TRUE,
      stderr = TRUE
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
  })
}
