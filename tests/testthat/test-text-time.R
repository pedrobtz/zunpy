# Strings, bytes, dates and times (design section 6.1; roadmap Stage 4)
# against NumPy's fixtures, and the conversions that refuse.

test_that("every string, bytes and time fixture decodes as NumPy wrote it", {
  m <- fixtures_manifest()
  m <- m[substr(m$descr, 2, 2) %in% c("S", "U", "V", "M", "m") &
           !startsWith(m$file, "edge-") & m$file != "dt-ns-now.npy", ]
  expect_gt(nrow(m), 20)
  for (i in seq_len(nrow(m))) {
    row <- m[i, ]
    expected <- fixture_expected(row)
    if (is.null(expected)) next
    expect_identical(npy_decode(fixture_bytes(row$file)), expected,
                     info = row$file)
  }
})

test_that("U reads in either byte order, trailing NULs stripped", {
  x <- npy_decode(fixture_bytes("U5-be-f.npy"))
  expect_identical(x, npy_decode(fixture_bytes("U5-le-c.npy")))
  expect_identical(x[1, ], c("", "a", "h\u00e9llo"))
  expect_identical(x[2, ], c("\u65e5\u672c", "\U0001F600x", "tab\tq"))
  expect_identical(Encoding(x[1, 3]), "UTF-8")
})

test_that("S: encoding, strings = 'raw', and NUL", {
  x <- fixture_bytes("edge-s-latin1.npy")
  e <- expect_zunpy_error(npy_decode(x), "zunpy_invalid_error")
  expect_identical(e$index, 1)
  expect_identical(npy_decode(x, encoding = "latin1"), "caf\u00e9")
  b <- npy_decode(x, encoding = "bytes")
  expect_identical(Encoding(b), "bytes")
  expect_identical(npy_decode(x, strings = "raw"), list(charToRaw("caf\xe9")))
  x <- fixture_bytes("edge-s-nul.npy")
  e <- expect_zunpy_error(npy_decode(x), "zunpy_unrepresentable")
  expect_identical(e$index, 1)
  expect_identical(npy_decode(x, strings = "raw"),
                   list(as.raw(c(0x61, 0, 0x62)), charToRaw("c")))
})

test_that("a surrogate in U is invalid", {
  e <- expect_zunpy_error(npy_decode(fixture_bytes("edge-u-surrogate.npy")),
                          "zunpy_invalid_error")
  expect_identical(e$index, 1)
})

test_that("V reads as a list of raw, NULs kept", {
  expect_identical(npy_decode(fixture_bytes("V3.npy")),
                   list(as.raw(c(1, 2, 0)), as.raw(c(0, 0, 9))))
})

test_that("dates and times take their R classes", {
  d <- npy_decode(fixture_bytes("dt-day.npy"))
  expect_s3_class(d, "Date")
  expect_identical(format(d), c("1970-01-01", "1969-12-31", "2024-10-08", NA))
  t <- npy_decode(fixture_bytes("dt-us.npy"))
  expect_s3_class(t, "POSIXct")
  expect_identical(attr(t, "tzone"), "UTC")
  expect_identical(format(t[1], "%Y-%m-%d %H:%M:%OS6"), "2024-10-08 12:00:00.123456")
  expect_true(is.na(t[3]))
  dt <- npy_decode(fixture_bytes("td-hour.npy"))
  expect_identical(units(dt), "hours")
  expect_identical(as.numeric(dt), c(1, 25, NA))
  expect_identical(units(npy_decode(fixture_bytes("td-week.npy"))), "weeks")
  expect_identical(as.numeric(npy_decode(fixture_bytes("td-ms.npy"))), c(1.5, -0.001))
})

test_that("M8[ns] beyond 2^53 is the nearest double; integer64 keeps it", {
  x <- fixture_bytes("dt-ns-now.npy")
  t <- npy_decode(x)
  expect_equal(as.numeric(t), 1728388800.123456789, tolerance = 1e-15)
  skip_if_not_installed("bit64")
  c64 <- npy_decode(x, datetime = "integer64")
  expect_s3_class(c64, "integer64")
  expect_identical(as.character(c64), "1728388800123456789")
  expect_identical(attr(c64, "npy_dtype"), "<M8[ns]")
})

test_that("units with no R class are integer64 counts with their dtype", {
  skip_if_not_installed("bit64")
  y <- npy_decode(fixture_bytes("dt-year.npy"))
  expect_s3_class(y, "integer64")
  expect_identical(attr(y, "npy_dtype"), "<M8[Y]")
  expect_identical(as.character(y), c("54", "-1", NA))
  ps <- npy_decode(fixture_bytes("td-ps.npy"))
  expect_identical(attr(ps, "npy_dtype"), "<m8[ps]")
})

test_that("a day count beyond 2^53 is unrepresentable", {
  e <- expect_zunpy_error(npy_decode(fixture_bytes("edge-td-day-big.npy")),
                          "zunpy_unrepresentable")
  expect_identical(e$index, 1)
})

test_that("re-encoding string and time fixtures gives NumPy's bytes", {
  m <- fixtures_manifest()
  # Little-endian, with an R class; dt-ns-now's count is beyond what a
  # double tells apart (design section 7.4), and V is read-only.
  files <- c("U5-le-c.npy", "U5-le-f.npy", "S4-c.npy", "S4-f.npy",
             "dt-day.npy", "dt-s.npy", "dt-ms.npy", "dt-us.npy", "dt-ns.npy",
             "dt-day-2d-c.npy", "td-day.npy", "td-hour.npy", "td-min.npy",
             "td-s.npy", "td-ms.npy", "td-us.npy", "td-ns.npy", "td-week.npy")
  for (f in files) {
    x <- fixture_bytes(f)
    h <- npy_header(x)
    y <- npy_encode(npy_decode(x), dtype = h$descr,
                    order = if (h$fortran_order) "F" else "C")
    expect_identical(y, x, info = f)
  }
  skip_if_not_installed("bit64")
  for (f in c("dt-year.npy", "dt-month.npy", "td-ps.npy")) {
    x <- fixture_bytes(f)
    expect_identical(npy_encode(npy_decode(x)), x, info = f)
  }
})

test_that("strings: width, NA, S encodings", {
  x <- c("a", "héllo", "\U0001F600")
  expect_identical(npy_dtype(x), "<U")
  expect_identical(npy_header(npy_encode(x))$descr, "<U5")
  expect_identical(npy_header(npy_encode(""))$descr, "<U1")
  expect_identical(npy_header(npy_encode(x, dtype = "|S"))$descr, "|S6")
  expect_identical(npy_decode(npy_encode(x, dtype = "<U8")), x)
  e <- expect_zunpy_error(npy_encode(x, dtype = "<U4"), "zunpy_range_error")
  expect_identical(e$index, 2)
  e <- expect_zunpy_error(npy_encode(c("a", NA)), "zunpy_na_error")
  expect_identical(e$index, 2)
  expect_identical(npy_decode(npy_encode(c("a", NA), na = "allow")), c("a", ""))
  l <- npy_encode("café", dtype = "|S", encoding = "latin1")
  expect_identical(npy_decode(l, strings = "raw"), list(charToRaw("caf\xe9")))
  expect_zunpy_error(npy_encode("日", dtype = "|S", encoding = "latin1"),
                     "zunpy_range_error")
  expect_identical(npy_decode(npy_encode(factor(c("b", "a")))), c("b", "a"))
  expect_zunpy_error(npy_encode("a", dtype = "<f8"), "zunpy_invalid_argument")
})

test_that("a Date stored as integer is written as its days", {
  d <- structure(c(19000L, NA), class = "Date")
  expect_identical(npy_decode(npy_encode(d)), structure(c(19000, NA), class = "Date"))
})

test_that("dates and times: exact or refused", {
  d <- as.Date(c("2024-10-08", NA, "1960-01-01"))
  expect_identical(npy_header(npy_encode(d))$descr, "<M8[D]")
  expect_identical(npy_decode(npy_encode(d)), d)
  expect_zunpy_error(npy_encode(structure(1.5, class = "Date")),
                     "zunpy_range_error")
  t <- as.POSIXct(c("2024-10-08 12:00:00.123456", NA), tz = "UTC")
  expect_identical(npy_header(npy_encode(t))$descr, "<M8[us]")
  expect_identical(npy_decode(npy_encode(t)), t)
  expect_identical(npy_header(npy_encode(t, unit = "ns"))$descr, "<M8[ns]")
  expect_identical(npy_decode(npy_encode(t, unit = "ns")), t)
  e <- expect_zunpy_error(npy_encode(t, unit = "ms"), "zunpy_range_error")
  expect_identical(e$index, 1)
  # A time zone is written as the instant, read back in UTC (design 7.4).
  local <- as.POSIXct("2024-10-08 12:00:00", tz = "Europe/Lisbon")
  back <- npy_decode(npy_encode(local, unit = "s"))
  expect_identical(as.numeric(back), as.numeric(local))
  expect_identical(attr(back, "tzone"), "UTC")
  dt <- as.difftime(c(1.5, NA), units = "hours")
  expect_zunpy_error(npy_encode(dt), "zunpy_range_error")
  expect_identical(npy_decode(npy_encode(dt, dtype = "<m8[s]")),
                   as.difftime(c(5400, NA), units = "secs"))
  expect_zunpy_error(npy_encode(t, dtype = "<m8[s]"), "zunpy_invalid_argument")
  expect_zunpy_error(npy_encode(d, dtype = "<M8[s]"), "zunpy_invalid_argument")
})

test_that("round trips over generated strings and times", {
  withr::local_seed(4)
  pool <- c("", "a", "héllo", "日本", "\U0001F600", "tab\tq",
            "x y")
  for (shape in list(5L, c(2L, 3L), c(3L, 0L), c(2L, 2L, 2L))) {
    for (order in c("F", "C")) {
      n <- prod(shape)
      s <- sample(pool, n, TRUE)
      d <- structure(as.double(sample(c(-1e4:1e4, NA), n, TRUE)), class = "Date")
      p <- structure(round(runif(n, -1e9, 2e9), 3), class = c("POSIXct", "POSIXt"),
                     tzone = "UTC")
      if (length(shape) > 1) {
        dim(s) <- shape
        dim(d) <- shape
        dim(p) <- shape
      }
      info <- paste(toString(shape), order)
      expect_identical(npy_decode(npy_encode(s, order = order)), s, info = info)
      expect_identical(npy_decode(npy_encode(d, order = order)), d, info = info)
      expect_identical(npy_decode(npy_encode(p, order = order, unit = "ms")), p,
                       info = info)
    }
  }
})
