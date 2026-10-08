# Paths, URLs and connections (roadmap Stage 7).

test_that("npy_write() and npy_read() round-trip through a path", {
  f <- withr::local_tempfile(fileext = ".npy")
  x <- array(seq_len(24) / 3, c(2, 3, 4))
  expect_identical(npy_write(x, f), f)
  expect_identical(npy_read(f), x)
  expect_identical(readBin(f, "raw", file.size(f)), npy_encode(x))
  npy_write(x, f, order = "C", dtype = "<f4")
  expect_identical(npy_header(f)$descr, "<f4")
  expect_false(npy_header(f)$fortran_order)
})

test_that("a .npz through a path, with names and npy_names()", {
  f <- withr::local_tempfile(fileext = ".npz")
  v <- list(a = 1:3, s = c("x", "y"), d = data.frame(k = 1:2))
  npy_write(v, f, compress = TRUE)
  expect_identical(npy_names(f), c("a", "s", "d"))
  expect_identical(npy_read(f), v)
  expect_identical(npy_read(f, names = "s"), v["s"])
})

test_that("connections: unopened ones are opened and closed, open ones left", {
  f <- withr::local_tempfile(fileext = ".npy")
  npy_write(1:5, f)
  # An unopened connection is opened and then closed, which destroys it.
  expect_identical(npy_read(file(f)), 1:5)
  con <- file(f, "rb")
  expect_identical(npy_read(con), 1:5)
  expect_true(isOpen(con))
  close(con)
  g <- withr::local_tempfile(fileext = ".npy")
  out <- file(g, "wb")
  npy_write(c(TRUE, FALSE), out)
  expect_true(isOpen(out))
  close(out)
  expect_identical(npy_read(g), c(TRUE, FALSE))
  txt <- file(f, "r")
  expect_zunpy_error(npy_read(txt), "zunpy_invalid_argument")
  close(txt)
})

test_that("a file:// URL reads like a path", {
  f <- withr::local_tempfile(fileext = ".npy")
  npy_write(matrix(1:4, 2), f)
  expect_identical(npy_read(paste0("file://", normalizePath(f))), matrix(1:4, 2))
})

test_that("max_size bounds a path before reading, a connection while reading", {
  f <- withr::local_tempfile(fileext = ".npy")
  npy_write(numeric(100), f)
  e <- expect_zunpy_error(npy_read(f, max_size = 500), "zunpy_size_limit")
  expect_identical(e$limit_value, 500)
  expect_zunpy_error(npy_read(file(f), max_size = 500), "zunpy_size_limit")
  expect_identical(length(npy_read(f, max_size = file.size(f))), 100L)
})

test_that("npy_header() on a file reads only the header", {
  f <- withr::local_tempfile(fileext = ".npy")
  npy_write(numeric(1e5), f)
  con <- file(f, "rb")
  h <- npy_header(con)
  expect_identical(h$shape, 1e5)
  # The connection is past the header and no further.
  expect_identical(seek(con), h$data_offset)
  close(con)
  expect_identical(npy_header(fixture_path("U5-le-c.npy"))$descr, "<U5")
  expect_identical(npy_header(fixture_path("rec-basic.npy"))$descr$name,
                   c("id", "x", "name", "flag", "t", "raw"))
})

test_that("bad paths and arguments are classed", {
  expect_zunpy_error(npy_read("no/such/file.npy"), "zunpy_invalid_argument")
  expect_zunpy_error(npy_read(tempdir()), "zunpy_invalid_argument")
  expect_zunpy_error(npy_read(1), "zunpy_invalid_argument")
  expect_zunpy_error(npy_write(1, NA_character_), "zunpy_invalid_argument")
  expect_zunpy_error(npy_write(1, file.path(tempdir(), "no", "dir", "x.npy")),
                     "zunpy_io_error")
})

test_that("the fast path and the long way agree", {
  # Little-endian f8, i4 and c16 are copied whole on a little-endian host;
  # the same values in other widths and byte orders go element by element.
  x <- c(1.5, NA, -0, Inf)
  expect_identical(npy_decode(npy_encode(x)), x)
  i <- c(1L, -7L, .Machine$integer.max)
  expect_identical(npy_decode(npy_encode(i)), i)
  e <- expect_zunpy_error(npy_encode(c(1L, NA)), "zunpy_na_error")
  expect_identical(e$index, 2)
  z <- complex(real = c(1, NA), imaginary = c(-2, 0))
  expect_identical(npy_decode(npy_encode(z)), z)
  be <- npy_decode(fixture_bytes("i4-be-c.npy"))
  le <- npy_decode(fixture_bytes("i4-le-c.npy"))
  expect_identical(be, le)
})

test_that("the direct read of a path agrees with the general path", {
  f <- withr::local_tempfile(fileext = ".npy")
  cases <- list(
    as.double(1:10), c(1L, -5L), complex(real = 1:3, imaginary = -1),
    matrix(as.double(1:6), 2), array(1:24, c(2, 3, 4))
  )
  for (x in cases) {
    for (order in c("F", "C")) {
      npy_write(x, f, order = order)
      bytes <- readBin(f, "raw", file.size(f))
      expect_identical(npy_read(f), npy_decode(bytes))
      expect_identical(npy_read(f, order = "file"), npy_decode(bytes, order = "file"))
    }
  }
  npy_write(c(1L, NA), f, na = "allow")
  e <- expect_zunpy_error(npy_read(f), "zunpy_na_error")
  expect_identical(e$index, 2)
  expect_identical(npy_read(f, na = "allow"), c(1L, NA))
  # A file with bytes after the data goes the general way, and is refused.
  cat("x", file = f, append = TRUE)
  expect_zunpy_error(npy_read(f), "zunpy_parse_error")
})
