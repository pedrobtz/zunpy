# Structured dtypes as data frames (design sections 6.3 and 7.3; roadmap
# Stage 5).

test_that("every structured fixture reads as NumPy wrote it", {
  m <- fixtures_manifest()
  m <- m[startsWith(m$file, "rec-"), ]
  expect_gt(nrow(m), 9)
  for (i in seq_len(nrow(m))) {
    row <- m[i, ]
    expect_identical(npy_decode(fixture_bytes(row$file)), fixture_expected(row),
                     info = row$file)
  }
})

test_that("fields keep their R types, subarrays expand, padding goes", {
  r <- npy_decode(fixture_bytes("rec-basic.npy"))
  expect_named(r, c("id", "x", "name", "flag", "t", "raw"))
  expect_type(r$id, "integer")
  expect_s3_class(r$t, "POSIXct")
  expect_identical(r$name[2], "héllo")
  s <- npy_decode(fixture_bytes("rec-subarray.npy"))
  expect_named(s, c("xyz.1", "xyz.2", "xyz.3", "m.1", "m.2", "m.3", "m.4", "k"))
  expect_identical(s$m.2, c(2L, 6L))
  a <- npy_decode(fixture_bytes("rec-aligned.npy"))
  expect_named(a, c("a", "b", "c"))
  expect_identical(a$b, c(2^40, -5))
  expect_named(npy_decode(fixture_bytes("rec-titles.npy")), c("a", "b"))
})

test_that("records with two dimensions carry npy_shape, in R's order", {
  c_order <- npy_decode(fixture_bytes("rec-2d-c.npy"))
  f_order <- npy_decode(fixture_bytes("rec-2d-f.npy"))
  expect_identical(c_order, f_order)
  expect_identical(attr(c_order, "npy_shape"), c(2, 3))
  # Row i of a 2 x 3 array in R's order is element [(i-1) %% 2, (i-1) %/% 2].
  expect_identical(c_order$v, c(0L, 3L, 1L, 4L, 2L, 5L))
  file <- npy_decode(fixture_bytes("rec-2d-c.npy"), order = "file")
  expect_identical(file$v, 0:5)
  expect_identical(attr(file, "npy_shape"), c(3, 2))
})

test_that("field names in Latin-1 and in UTF-8", {
  expect_named(npy_decode(fixture_bytes("rec-latin1-name.npy")), "café")
  expect_identical(npy_header(fixture_bytes("rec-utf8-name.npy"))$version, "3.0")
  expect_named(npy_decode(fixture_bytes("rec-utf8-name.npy")), c("€", "b"))
})

test_that("an empty structured array is a data frame with no rows", {
  r <- npy_decode(fixture_bytes("rec-empty.npy"))
  expect_identical(nrow(r), 0L)
  expect_named(r, c("id", "x", "name", "flag", "t", "raw"))
})

test_that("a data frame writes as NumPy writes the same record array", {
  for (f in c("rec-basic.npy", "rec-latin1-name.npy", "rec-utf8-name.npy",
              "rec-2d-f.npy", "rec-empty.npy")) {
    x <- fixture_bytes(f)
    r <- npy_decode(x)
    h <- npy_header(x)
    dtype <- stats::setNames(h$descr$descr, h$descr$name)
    expect_identical(npy_encode(r, dtype = dtype), x, info = f)
  }
  x <- fixture_bytes("rec-2d-c.npy")
  expect_identical(npy_encode(npy_decode(x), order = "C"), x)
})

test_that("data frames round-trip", {
  df <- data.frame(
    id = 1:3, x = c(1.5, NA, -0), s = c("a", "bé", ""),
    d = as.Date("2024-01-01") + 0:2, b = c(TRUE, FALSE, TRUE),
    f = factor(c("u", "v", "u")), stringsAsFactors = FALSE
  )
  back <- npy_decode(npy_encode(df))
  df$f <- as.character(df$f)  # factors are written as their labels
  expect_identical(back, df)
  h <- npy_header(npy_encode(df, dtype = c(id = "|u1", x = "<f4")))
  expect_identical(h$descr$descr, c("|u1", "<f4", "<U2", "<M8[D]", "|b1", "<U1"))
  expect_identical(h$itemsize, 1 + 4 + 8 + 8 + 1 + 4)
})

test_that("row names, titles and subarray shapes are not kept", {
  df <- data.frame(a = 1:2, row.names = c("x", "y"))
  expect_identical(attr(npy_decode(npy_encode(df)), "row.names"), 1:2)
})

test_that("writing refuses what a field cannot hold", {
  e <- expect_zunpy_error(npy_encode(data.frame(a = c(1, 300)), dtype = c(a = "|u1")),
                          "zunpy_range_error")
  expect_identical(e$index, 2)
  expect_match(conditionMessage(e), "column 'a'")
  expect_zunpy_error(npy_encode(data.frame(a = c("x", NA))), "zunpy_na_error")
  df <- data.frame(a = 1)
  df$l <- list(1:2)
  expect_zunpy_error(npy_encode(df), "zunpy_unsupported_type")
  bad <- data.frame(a = 1, b = 2)
  names(bad) <- c("a", "a")
  expect_zunpy_error(npy_encode(bad), "zunpy_invalid_argument")
  names(bad) <- c("a", "")
  expect_zunpy_error(npy_encode(bad), "zunpy_invalid_argument")
  expect_zunpy_error(npy_encode(data.frame(a = 1), dtype = c(zz = "<f4")),
                     "zunpy_invalid_argument")
})

test_that("field names are written as Python's repr() writes them", {
  df <- data.frame(1, 2, 3, 4)
  names(df) <- c("it's", "say \"hi\"", "tab\there", "back\\slash")
  x <- npy_encode(df)
  h <- rawToChar(x[11:npy_header(x)$data_offset])
  expect_match(h, "(\"it's\", '<f8')", fixed = TRUE)
  expect_match(h, "('say \"hi\"', '<f8')", fixed = TRUE)
  expect_match(h, "('tab\\there', '<f8')", fixed = TRUE)
  expect_match(h, "('back\\\\slash', '<f8')", fixed = TRUE)
  expect_named(npy_decode(x), names(df))
})
