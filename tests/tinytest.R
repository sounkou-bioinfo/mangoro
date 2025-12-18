# Trigger tinytest during R CMD check / install-time tests
tinytest::test_package(
  "mangoro",
  testdir = system.file("tinytest", package = "mangoro")
)
