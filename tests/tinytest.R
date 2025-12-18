# Trigger tinytest during R CMD check / install-time tests
if (requireNamespace("tinytest", quietly = TRUE)) {
  tinytest::test_package("mangoro", testdir = system.file("tinytest", package = "mangoro"))
} else {
  warning("tinytest not installed; skipping tests")
}
