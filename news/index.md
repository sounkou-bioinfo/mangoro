# Changelog

## mangoro 0.2.15

- Add
  [`go_binary_candidates()`](https://sounkou-bioinfo.github.io/mangoro/reference/go_binary_candidates.md)
  and strengthen Go discovery/validation (platform-specific search
  paths, `go version` validation, and minimum Go version check).
- Tinytest now checks Go candidates first and emits a short warning
  before skipping when Go is unavailable or unsuitable.
- `find_go()` now warns when it falls back to PATH or platform defaults
  instead of an explicit user-provided Go path.

## mangoro 0.2.14

- Skips tests by default by checking environment variable
  “RUN_MANGORO_TINYTEST”

## mangoro 0.2.13

- Added Go path overrides (`options(mangoro.go_path)` / `MANGORO_GO`)
  with clearer platform messaging; Go path checks now occur at runtime
  only.
- Add tinytest `tests/tinytest.R`

## mangoro 0.2.12

- Fixed leftover temp directory detritus: Configure scripts now use a
  predictable temp directory path (`${TMPDIR:-/tmp}/mangoro_go_home_$$`)
  instead of `mktemp -d` to ensure proper cleanup and avoid leaving
  temporary files in the check directory.

## mangoro 0.2.11

- Fixes `~/.config/go` directory creation: All Go invocations (in
  configure scripts and R functions) now temporarily set `HOME` to a
  temporary directory to prevent Go’s telemetry system from writing to
  `~/.config/go`. This is necessary because Go 1.23+ writes telemetry
  data to `os.UserConfigDir()` even for simple commands like
  `go version`. Both configure and configure.win scripts, as well as
  [`mangoro_go_build()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_go_build.md),
  [`get_mangos_version()`](https://sounkou-bioinfo.github.io/mangoro/reference/get_mangos_version.md),
  and
  [`get_arrow_go_version()`](https://sounkou-bioinfo.github.io/mangoro/reference/get_arrow_go_version.md)
  functions are now isolated. All environment variables are restored and
  temporary directories cleaned up after completion. This resolves the
  CRAN policy violation that caused the previous archive.

## mangoro 0.2.10

- Go build telemetry and ~/.config side effect: The package now controls
  Go telemetry during build (default: off) and avoids populating
  ~/.config/go/telemetry and other user config/cache directories during
  installation and tests, complying with CRAN policy.
- Added a `telemetry` parameter to
  [`mangoro_go_build()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_go_build.md)
  for explicit control of Go telemetry mode.
- Configure improvements: The configure script now creates a config.log
  file for diagnostics and logging, improving reliability and
  transparency. Installation failures due to missing Go are now logged,
  and the script avoids suppressing diagnostics.

## mangoro 0.2.6

CRAN release: 2025-11-25

- actually remove the generate_certs.R script from the package build

## mangoro 0.2.5

### CRAN Policy Compliance

- Replaced non-suppressible console output
  ([`print()`](https://rdrr.io/r/base/print.html)/[`cat()`](https://rdrr.io/r/base/cat.html))
  with [`message()`](https://rdrr.io/r/base/message.html) where
  appropriate (notably
  [`mangoro_go_build()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_go_build.md)),
  so information.
- Updated `tools/generate_certs.R` to avoid writing into the package or
  user home by default: when no explicit `--dir` is provided it writes
  into a temporary directory and reports the chosen path via
  [`message()`](https://rdrr.io/r/base/message.html); the script still
  accepts an explicit `--dir` for persistent output.
- Added `inst/AUTHORS` and `inst/COPYRIGHTS` so vendored components and
  their license files are easy to find; full license/NOTICE/AUTHORS
  files remain in the vendor directories.
- Added `LICENSE.note` summarizing the license types present in vendored
  code.
- Added `Copyright: See inst/AUTHORS` to `DESCRIPTION` to make copyright
  ownership explicit as requested by CRAN.

## mangoro 0.2.4

### DESCRIPTION File Updates

- Added single quotes around all software names in Title and Description
  fields (‘R’, ‘Go’, ‘IPC’, ‘Nanomsg’, ‘nanonext’, ‘nanoarrow’) to
  comply with CRAN requirements

## mangoro 0.2.3

### CRAN Policy Compliance

- [`mangoro_go_build()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_go_build.md)
  now sets `GOCACHE` to a temporary directory by default to prevent
  populating `~/.cache/go-build` during package checks, complying with
  CRAN policy
- Added `gocache` parameter to
  [`mangoro_go_build()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_go_build.md)
  for users who want to specify a custom cache location or use the
  default Go cache (`gocache = NA`)
- Maintains backward compatibility while ensuring CRAN compliance

## mangoro 0.2.2

### CRAN Packaging Improvements

- Fixed long path warnings by relocating flatbuf files during build
  process
- Flatbuf files now stored in `tools/flatbuf/` and restored during
  package installation via configure script
- Configure scripts updated to be POSIX-compliant (replaced bashisms
  with standard sh syntax)
- Moved `processx` from Imports to Suggests (only used in tests)
- Package now passes `R CMD check --as-cran` with no warnings

### Internal Changes

- Updated `tools/vendorMangos.sh` to move flatbuf files to tools
  directory after vendoring
- Enhanced configure/configure.win scripts to restore flatbuf files
  during installation
- Excluded `inst/go/vendor/.../flatbuf` directory from package tarball
  via .Rbuildignore

## mangoro 0.2.1

### RPC Interface

- New `rgoipc` Go package for type-safe function registration with Arrow
  schema validation
- RPC protocol wrapping Arrow IPC data with function call envelope
- RPC helper functions:
  [`mangoro_rpc_get_manifest()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_rpc_get_manifest.md),
  [`mangoro_rpc_call()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_rpc_call.md),
  [`mangoro_rpc_send()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_rpc_send.md),
  [`mangoro_rpc_recv()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_rpc_recv.md),
  [`mangoro_rpc_parse_response()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_rpc_parse_response.md)
- RPC example server demonstrating function registration (add,
  echoString functions)
- HTTP file server with RPC control interface (start/stop/status
  commands)
- Helper functions for HTTP server control:
  [`mangoro_http_start()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_http_start.md),
  [`mangoro_http_stop()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_http_stop.md),
  [`mangoro_http_status()`](https://sounkou-bioinfo.github.io/mangoro/reference/mangoro_http_status.md)

### Examples

- Complete RPC function registration and calling example in README
- HTTP server RPC control demonstration with server output capture
- Arrow IPC-based RPC communication examples

## mangoro 0.2.0

### Initial Release

- R/Go IPC using Nanomsg Next Gen (mangos v3, nanonext)
- Vendored Go dependencies for reproducible builds
- Helper functions to build and run Go binaries from R
- Example echo server and on-the-fly Go compilation from R
- Platform-correct IPC path helpers
- Designed for extensibility and cross-platform use
- We do not cgo’s c-shared mode to avoid loading multiple Go runtimes in
  the same R session

### Arrow Go IPC Support

- Add Arrow Go IPC roundtrip example and support: send and receive Arrow
  IPC streams between R and Go using nanoarrow and arrow-go.
- New function:
  [`get_arrow_go_version()`](https://sounkou-bioinfo.github.io/mangoro/reference/get_arrow_go_version.md)
  to report the vendored Arrow Go version.
