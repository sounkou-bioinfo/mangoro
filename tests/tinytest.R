# tinytest
if (requireNamespace("tinytest", quietly = TRUE)) {
  tinytest::test_package(
    "mangoro",
    testdir = system.file("tinytest", package = "mangoro")
  )
}
