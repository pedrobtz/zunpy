# Expect a zunpy condition of `class`, and return it for field checks.
expect_zunpy_error <- function(expr, class) {
  e <- tryCatch(expr, zunpy_error = function(e) e)
  # expect_s3_class() with several classes passes on any one of them, so
  # each class is asserted on its own.
  testthat::expect_s3_class(e, "zunpy_error")
  for (cl in class) testthat::expect_s3_class(e, cl)
  invisible(e)
}
