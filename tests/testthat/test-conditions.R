test_that("every condition inherits zunpy_error and carries its fields", {
  e <- tryCatch(znp_invalid_argument("dtype", "bad"), error = identity)
  expect_s3_class(e, c("zunpy_invalid_argument", "zunpy_error", "error"))
  expect_identical(e$arg, "dtype")

  e <- tryCatch(znp_parse_error(10, "bad"), error = identity)
  expect_s3_class(e, "zunpy_parse_error")
  expect_identical(e$offset, 10)
  expect_null(e$member)

  e <- tryCatch(znp_invalid_error(64, "bad", member = "x"), error = identity)
  expect_s3_class(e, "zunpy_invalid_error")
  expect_identical(e$offset, 64)
  expect_identical(e$member, "x")

  e <- tryCatch(znp_unsupported_type("|O", "bad"), error = identity)
  expect_s3_class(e, "zunpy_unsupported_type")
  expect_identical(e$dtype, "|O")

  e <- tryCatch(znp_unrepresentable("bad", offset = 12, index = 3),
                error = identity)
  expect_s3_class(e, "zunpy_unrepresentable")
  expect_identical(e$offset, 12)
  expect_identical(e$index, 3)

  e <- tryCatch(znp_na_error(2, "bad"), error = identity)
  expect_s3_class(e, "zunpy_na_error")
  expect_identical(e$index, 2)

  e <- tryCatch(znp_range_error(5, "bad"), error = identity)
  expect_s3_class(e, "zunpy_range_error")
  expect_identical(e$index, 5)

  expect_error(znp_io_error("x"), class = "zunpy_io_error")
})

test_that("each limit has its own subclass under zunpy_limit_error", {
  subclasses <- c(
    max_size = "zunpy_size_limit",
    max_header = "zunpy_header_limit",
    max_dims = "zunpy_dims_limit",
    max_members = "zunpy_members_limit"
  )
  for (limit in names(subclasses)) {
    e <- tryCatch(znp_limit_error(limit, 10, "too big"), error = identity)
    expect_s3_class(e, c(subclasses[[limit]], "zunpy_limit_error",
                         "zunpy_error"))
    expect_identical(e$limit, limit)
    expect_identical(e$limit_value, 10)
  }

  e <- tryCatch(znp_limit_error("max_fields", 1024, "too many"),
                error = identity)
  expect_identical(class(e)[1:2], c("zunpy_limit_error", "zunpy_error"))
})
