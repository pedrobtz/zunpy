# Expect a zunpy condition of `class`, and return it for field checks.
expect_zunpy_error <- function(expr, class) {
  e <- tryCatch(expr, zunpy_error = function(e) e)
  testthat::expect_s3_class(e, c(class, "zunpy_error"))
  invisible(e)
}
