# npy_decode() against every numeric, boolean and complex fixture NumPy
# wrote (tools/make-fixtures.py), in both byte orders and both memory orders.

test_that("every plain fixture decodes to the values NumPy wrote", {
  m <- fixtures_manifest()
  m <- m[!startsWith(m$file, "edge-"), ]
  expect_gt(nrow(m), 50)
  for (i in seq_len(nrow(m))) {
    row <- m[i, ]
    got <- npy_decode(fixture_bytes(row$file))
    expect_identical(got, fixture_expected(row), info = row$file)
  }
})

test_that("signed zeros and NaN survive", {
  x <- npy_decode(fixture_bytes("f8-le-c.npy"))
  expect_identical(1 / x[1, 1, 2], -Inf)
  expect_true(is.nan(x[1, 2, 3]))
  x <- npy_decode(fixture_bytes("f2-be-f.npy"))
  expect_identical(1 / x[1, 1, 2], -Inf)
})

test_that("order = 'file' keeps the file's memory order", {
  m <- fixtures_manifest()
  for (f in c("f8-le-c.npy", "i2-be-c.npy", "shape-5d-c.npy", "c16-le-c.npy")) {
    row <- m[m$file == f, ]
    expected <- fixture_expected(row)
    got <- npy_decode(fixture_bytes(f), order = "file")
    k <- length(dim(expected))
    expect_identical(got, aperm(expected, k:1), info = f)
  }
  # A Fortran-order file is the same either way.
  x <- fixture_bytes("f8-le-f.npy")
  expect_identical(npy_decode(x, order = "file"), npy_decode(x))
})

test_that("0-d and 1-d arrays have no dim; empty arrays keep theirs", {
  x <- npy_decode(fixture_bytes("shape-scalar.npy"))
  expect_null(dim(x))
  expect_length(x, 1)
  expect_null(dim(npy_decode(fixture_bytes("shape-vector.npy"))))
  expect_identical(dim(npy_decode(fixture_bytes("shape-empty.npy"))), c(0L, 3L))
})

test_that("i4's -2^31 is NA only on request", {
  x <- fixture_bytes("edge-i4-min.npy")
  e <- expect_zunpy_error(npy_decode(x), "zunpy_na_error")
  expect_identical(e$index, 2)
  expect_identical(npy_decode(x, na = "allow"), c(1L, NA, 3L))
})

test_that("64-bit integers beyond 2^53 need integer64", {
  x <- fixture_bytes("edge-i8-big.npy")
  e <- expect_zunpy_error(npy_decode(x), "zunpy_unrepresentable")
  expect_identical(e$index, 2)
  expect_identical(e$offset, 128 + 8)
  x <- fixture_bytes("edge-u8-big.npy")
  expect_zunpy_error(npy_decode(x), "zunpy_unrepresentable")

  skip_if_not_installed("bit64")
  v <- npy_decode(fixture_bytes("edge-i8-big.npy"), int64 = "integer64")
  expect_s3_class(v, "integer64")
  expect_identical(as.character(v),
                   c("0", "9007199254740993", "-9007199254740993"))
  v <- npy_decode(fixture_bytes("edge-u8-big.npy"), int64 = "integer64")
  expect_identical(as.character(v)[3], "9223372036854775807")
})

test_that("u8 at 2^63 and i8's NA pattern are refused as integer64", {
  e <- expect_zunpy_error(
    npy_decode(fixture_bytes("edge-u8-top.npy"), int64 = "integer64"),
    "zunpy_unrepresentable"
  )
  expect_identical(e$index, 2)
  x <- fixture_bytes("edge-i8-min.npy")
  expect_zunpy_error(npy_decode(x, int64 = "integer64"), "zunpy_na_error")
  skip_if_not_installed("bit64")
  v <- npy_decode(x, int64 = "integer64", na = "allow")
  expect_identical(is.na(v), c(FALSE, TRUE))
})

test_that("a dimension above 2^31 - 1 is unrepresentable", {
  x <- npy_header_bytes(npy_dict("'<f8'", "(2147483648, 0)"))
  e <- expect_zunpy_error(npy_decode(x), "zunpy_unrepresentable")
  expect_true(is.na(e$index))
})

test_that("dtypes of later stages are refused, classed", {
  x <- npy_header_bytes(npy_dict("'<U2'"), raw(8))
  e <- expect_zunpy_error(npy_decode(x), "zunpy_unsupported_type")
  expect_identical(e$dtype, "<U2")
})

test_that("a native byte order and 16-byte alignment warn", {
  x <- npy_header_bytes(npy_dict("'=f8'"), raw(8))
  expect_warning(v <- npy_decode(x), class = "zunpy_byte_order")
  expect_identical(v, 0)
  x <- npy_header_bytes(npy_dict("'<f8'"), raw(8), align = 16L)
  expect_warning(npy_decode(x), class = "zunpy_alignment")
})

test_that("arguments are checked", {
  x <- fixture_bytes("shape-vector.npy")
  expect_zunpy_error(npy_decode(x, order = "C"), "zunpy_invalid_argument")
  expect_zunpy_error(npy_decode(x, int64 = 1), "zunpy_invalid_argument")
  expect_zunpy_error(npy_decode(x, na = NA), "zunpy_invalid_argument")
  expect_zunpy_error(npy_decode("x"), "zunpy_invalid_argument")
})

test_that("npy_header() reads a header without its data", {
  x <- fixture_bytes("f8-le-c.npy")
  h <- npy_header(x[1:128])
  expect_identical(h$version, "1.0")
  expect_identical(h$descr, "<f8")
  expect_identical(h$shape, c(2, 3, 4))
  expect_false(h$fortran_order)
  expect_identical(h$itemsize, 8)
  expect_identical(h$data_offset, 128)
  expect_identical(npy_header(x), h)
  d <- "{'descr': [('a', '<u4'), ('b', '<f8', (3,))], 'fortran_order': False, 'shape': (2,), }"
  h <- npy_header(npy_header_bytes(d))
  expect_identical(h$descr$name, c("a", "b"))
  expect_identical(h$descr$shape, list(numeric(), 3))
})
