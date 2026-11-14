# The writer's R/native boundary (#25): R objects and their attributes are
# not a memory-safety boundary, so every size and shape the native writer
# relies on is checked twice, in R with a classed error and in C with a
# status. The C checks are reached here by calling the entry points with
# arguments R would never pass.

test_that("#25 a data frame whose columns are not nrow long is refused", {
  forged <- structure(list(a = 1:3), class = "data.frame", row.names = 1:2)
  expect_zunpy_error(npy_encode(forged), "zunpy_invalid_argument")
  short <- structure(list(a = 1:2, b = 1:3), class = "data.frame",
                     row.names = 1:3)
  expect_zunpy_error(npy_encode(short), "zunpy_invalid_argument")
  empty <- structure(list(a = integer()), class = "data.frame",
                     row.names = 1:2)
  expect_zunpy_error(npy_encode(empty), "zunpy_invalid_argument")
})

test_that("#25 npy_shape must be whole, finite, non-negative and match", {
  x <- data.frame(a = 1:4)
  bad <- list(
    c(0.5, 8), c(-1, -4), c(-2, -2), c(NA, 4), c(NaN, 4), c(Inf, 0),
    c(4, Inf), "4", TRUE, c(2, 3), 2^60 * c(1, 1), numeric(), rep(1, 65),
    c(2^53 + 2, 0)
  )
  for (s in bad) {
    attr(x, "npy_shape") <- s
    expect_zunpy_error(npy_encode(x), "zunpy_invalid_argument")
  }
  attr(x, "npy_shape") <- c(2L, 2L)
  y <- npy_decode(npy_encode(x))
  expect_identical(attr(y, "npy_shape"), c(2, 2))
  expect_identical(y$a, 1:4)
})

test_that("#25 an empty data frame with a zero-length npy_shape axis", {
  x <- data.frame(a = integer())
  attr(x, "npy_shape") <- c(0, 3)
  y <- npy_decode(npy_encode(x))
  expect_identical(nrow(y), 0L)
  expect_identical(npy_header(npy_encode(x))$shape, c(0, 3))
})

# The native entry points, called with what R's checks would refuse. Each
# must return a status, never write past what it allocated. The spec is
# list(kind, width, unit, scale), here <i4.
test_that("#25 native zunpy_encode_records refuses a column of the wrong length", {
  spec_i4 <- list("i", 4L, "", 0)
  res <- .Call(zunpy:::zunpy_encode_records, list(1:3), list(spec_i4), "a",
               2, c(0L, 0L), FALSE)
  expect_identical(res$status, "ZNP_WRITE_SHAPE")
  expect_identical(res$column, 1L)
  res <- .Call(zunpy:::zunpy_encode_records, list(1:2, 1:1), list(spec_i4, spec_i4),
               c("a", "b"), 2, c(0L, 0L), c(FALSE, FALSE))
  expect_identical(res$status, "ZNP_WRITE_SHAPE")
  expect_identical(res$column, 2L)
})

test_that("#25 native zunpy_encode_records refuses a hostile shape", {
  spec_i4 <- list("i", 4L, "", 0)
  for (s in list(c(0.5, 4), c(-1, -2), c(NA, 2), c(Inf, 0), c(2^62, 2^62),
                 c(2^53 + 2, 0), rep(1, 65))) {
    res <- .Call(zunpy:::zunpy_encode_records, list(1:2), list(spec_i4), "a",
                 as.double(s), c(0L, 0L), FALSE)
    expect_identical(res$status, "ZNP_WRITE_SHAPE", info = paste(s, collapse = ","))
  }
})

test_that("#25 native zunpy_encode_records refuses an invalid UTF-8 name", {
  spec_i4 <- list("i", 4L, "", 0)
  nm <- "a\xff"
  Encoding(nm) <- "bytes"
  res <- .Call(zunpy:::zunpy_encode_records, list(1:2), list(spec_i4), nm,
               2, c(0L, 0L), FALSE)
  expect_identical(res$status, "ZNP_WRITE_NAME")
  expect_identical(res$column, 1L)
})

test_that("#25 native zunpy_encode refuses a shape that is not the length", {
  spec_i4 <- list("i", 4L, "", 0)
  for (s in list(3, c(2, 2), c(0.5, 4), c(-1, -2), NA_real_, Inf, rep(1, 65),
                 c(2^62, 2^62))) {
    res <- .Call(zunpy:::zunpy_encode, 1:2, spec_i4, as.double(s),
                 c(0L, 0L, 0L))
    expect_identical(res$status, "ZNP_WRITE_SHAPE", info = paste(s, collapse = ","))
  }
  res <- .Call(zunpy:::zunpy_encode, 1:4, spec_i4, c(2, 2), c(0L, 0L, 0L))
  expect_identical(res$status, "ZNP_OK")
})
