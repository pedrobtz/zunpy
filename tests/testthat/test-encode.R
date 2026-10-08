# npy_encode() (design sections 7 and 8): byte-identical to NumPy, exact or
# refused, and a round trip through npy_decode().

test_that("re-encoding a NumPy fixture gives NumPy's bytes", {
  m <- fixtures_manifest()
  # Big-endian fixtures cannot match (zunpy writes little-endian), and R has
  # no 0-d array (shape-scalar comes back as (1,)).
  m <- m[!startsWith(m$file, "edge-") & !startsWith(m$descr, ">") &
           m$file != "shape-scalar.npy" &
           substr(m$descr, 2, 2) %in% c("b", "i", "u", "f", "c"), ]
  expect_gt(nrow(m), 30)
  for (f in m$file) {
    x <- fixture_bytes(f)
    h <- npy_header(x)
    y <- npy_encode(npy_decode(x), dtype = h$descr,
                    order = if (h$fortran_order) "F" else "C")
    expect_identical(y, x, info = f)
  }
})

test_that("the default dtypes follow the R type", {
  expect_identical(npy_dtype(TRUE), "|b1")
  expect_identical(npy_dtype(1L), "<i4")
  expect_identical(npy_dtype(1), "<f8")
  expect_identical(npy_dtype(1i), "<c16")
  expect_identical(npy_dtype(as.raw(1)), "|u1")
  expect_identical(npy_dtype(matrix(1L, 2, 2)), "<i4")
  # Whole doubles stay doubles (D3).
  expect_identical(npy_header(npy_encode(c(1, 2)))$descr, "<f8")
})

test_that("the header is NumPy's, byte for byte", {
  x <- npy_encode(c(1.5, 2.5, 3.5))
  dict <- "{'descr': '<f8', 'fortran_order': False, 'shape': (3,), }"
  expect_identical(rawToChar(x[11:(10 + nchar(dict))]), dict)
  expect_identical(length(x) %% 64, 24)  # 128 bytes of header, 24 of data
  expect_identical(x[128], as.raw(0x0a))
  h <- npy_header(npy_encode(matrix(1:6, 2)))
  expect_true(h$fortran_order)
  expect_identical(h$shape, c(2, 3))
  expect_false(npy_header(npy_encode(matrix(1:6, 2), order = "C"))$fortran_order)
  # Both C- and Fortran-contiguous: NumPy writes C order.
  expect_false(npy_header(npy_encode(matrix(1:3, 1)))$fortran_order)
  expect_false(npy_header(npy_encode(matrix(integer(), 0, 3)))$fortran_order)
})

test_that("writing is deterministic", {
  x <- array(seq_len(24) / 7, c(2, 3, 4))
  expect_identical(npy_encode(x), npy_encode(x))
  expect_identical(npy_encode(x, order = "C"), npy_encode(x, order = "C"))
})

test_that("round trips are identical over generated arrays", {
  withr::local_seed(20261008)
  gen <- list(
    logical = function(n) sample(c(TRUE, FALSE), n, TRUE),
    integer = function(n) sample(c(-.Machine$integer.max, -1L, 0L, 7L,
                                   .Machine$integer.max), n, TRUE),
    double = function(n) sample(c(0, -0, 1.5, -2.25, Inf, -Inf, NaN, NA,
                                  .Machine$double.xmax, 5e-324), n, TRUE),
    complex = function(n) complex(real = rnorm(n), imaginary = c(NA, Inf, rnorm(n))[seq_len(n)])
  )
  shapes <- list(1L, 5L, 0L, c(2L, 3L), c(3L, 0L), c(1L, 4L), c(2L, 3L, 4L),
                 c(2L, 1L, 2L, 3L))
  count <- 0
  for (type in names(gen)) {
    for (shape in shapes) {
      for (order in c("F", "C")) {
        n <- prod(shape)
        x <- gen[[type]](n)
        if (length(shape) > 1) dim(x) <- shape
        bytes <- npy_encode(x, order = order)
        expect_identical(npy_encode(x, order = order), bytes)
        expect_identical(npy_decode(bytes), x, info = paste(type, order,
                                                             toString(shape)))
        count <- count + 1
      }
    }
  }
  expect_identical(count, 64)
})

test_that("NA_real_ keeps its payload; NaN stays NaN", {
  x <- npy_decode(npy_encode(c(NA, NaN, 1)))
  expect_identical(is.na(x) & !is.nan(x), c(TRUE, FALSE, FALSE))
  expect_true(is.nan(x[2]))
})

test_that("dtype narrows exactly or refuses, naming the index", {
  expect_identical(npy_decode(npy_encode(c(1, 2, 300), dtype = "<i2")),
                   c(1L, 2L, 300L))
  e <- expect_zunpy_error(npy_encode(c(1, 2, 40000), dtype = "<i2"),
                          "zunpy_range_error")
  expect_identical(e$index, 3)
  expect_zunpy_error(npy_encode(1.5, dtype = "<i4"), "zunpy_range_error")
  expect_zunpy_error(npy_encode(-1L, dtype = "|u1"), "zunpy_range_error")
  expect_zunpy_error(npy_encode(2L, dtype = "|b1"), "zunpy_range_error")
  # Floats round to nearest even.
  expect_identical(npy_decode(npy_encode(1 + 2^-30, dtype = "<f4")), 1)
  expect_identical(npy_decode(npy_encode(65520, dtype = "<f2")), Inf)
  expect_identical(npy_decode(npy_encode(1:3, dtype = "<f8")), c(1, 2, 3))
  expect_identical(npy_decode(npy_encode(c(TRUE, FALSE), dtype = "|u1")),
                   c(1L, 0L))
  expect_identical(npy_decode(npy_encode(2^53, dtype = "<i8")), 2^53)
  expect_identical(npy_decode(npy_encode(1i, dtype = "<c8")), 1i)
})

test_that("NA in a type without one is refused unless allowed", {
  e <- expect_zunpy_error(npy_encode(c(TRUE, NA)), "zunpy_na_error")
  expect_identical(e$index, 2)
  expect_warning(x <- npy_encode(c(TRUE, NA), na = "allow"),
                 class = "zunpy_na_replaced")
  expect_identical(npy_decode(x), c(TRUE, FALSE))

  expect_zunpy_error(npy_encode(c(1L, NA)), "zunpy_na_error")
  x <- npy_encode(c(1L, NA), na = "allow")
  expect_identical(npy_decode(x, na = "allow"), c(1L, NA))
  expect_zunpy_error(npy_decode(x), "zunpy_na_error")
  expect_zunpy_error(npy_encode(c(1L, NA), dtype = "<f8"), "zunpy_na_error")
  expect_identical(npy_decode(npy_encode(c(1L, NA), dtype = "<f8", na = "allow")),
                   c(1, NA))
  expect_zunpy_error(npy_encode(c(1, NA), dtype = "<i2"), "zunpy_na_error")
})

test_that("raw writes |u1, which reads back as integer", {
  x <- npy_encode(as.raw(c(0, 255)))
  expect_identical(npy_header(x)$descr, "|u1")
  expect_identical(npy_decode(x), c(0L, 255L))
})

test_that("integer64 writes <i8 and reads back", {
  skip_if_not_installed("bit64")
  x <- bit64::as.integer64(c("9007199254740993", "-5"))
  b <- npy_encode(x)
  expect_identical(npy_header(b)$descr, "<i8")
  expect_identical(npy_decode(b, int64 = "integer64"), x)
  expect_zunpy_error(npy_encode(bit64::as.integer64(-1), dtype = "<u8"),
                     "zunpy_range_error")
})

test_that("unsupported values and bad arguments are refused", {
  expect_zunpy_error(npy_encode(data.frame(a = 1)), "zunpy_unsupported_type")
  expect_zunpy_error(npy_encode(list(1)), "zunpy_unsupported_type")
  expect_zunpy_error(npy_encode(NULL), "zunpy_unsupported_type")
  expect_zunpy_error(npy_encode(1, dtype = "<c16"), "zunpy_invalid_argument")
  expect_zunpy_error(npy_encode(1, dtype = ">f8"), "zunpy_invalid_argument")
  expect_zunpy_error(npy_encode(1, dtype = c("<f8", "<f4")), "zunpy_invalid_argument")
  expect_zunpy_error(npy_encode(1, order = "X"), "zunpy_invalid_argument")
})

test_that("dimnames and names are dropped", {
  x <- matrix(1:4, 2, dimnames = list(c("a", "b"), NULL))
  expect_identical(npy_decode(npy_encode(x)), unname(x))
  expect_identical(npy_decode(npy_encode(c(a = 1, b = 2))), c(1, 2))
})
