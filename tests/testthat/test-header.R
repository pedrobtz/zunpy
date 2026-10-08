# The header grammar of design sections 9.1-9.3, on headers NumPy writes and
# on the variations the grammar allows.

test_that("a plain header gives its plan", {
  p <- check_dict(npy_dict("'<f8'", "(3, 4)"), raw(96))
  expect_identical(p$version, c(1L, 0L))
  expect_identical(p$descr, "<f8")
  expect_identical(p$shape, c(3, 4))
  expect_identical(p$count, 12)
  expect_identical(p$itemsize, 8)
  expect_false(p$fortran_order)
  expect_identical(p$data_offset, 128)
  expect_true(p$align64)
  expect_false(p$native_order)
  expect_null(p$fields)
})

test_that("every scalar dtype of section 6.1 is accepted", {
  ok <- c("|b1", "|i1", "<i2", "<i4", "<i8", "|u1", "<u2", ">u4", "<u8",
          "<f2", ">f4", "<f8", "<c8", ">c16", "|S5", "|S0", "<U3", ">U1",
          "|V4", "<M8[D]", "<M8[s]", "<M8[ms]", "<M8[us]", "<M8[ns]",
          "<M8[Y]", "<m8[h]", "<m8[as]")
  size <- c(1, 1, 2, 4, 8, 1, 2, 4, 8, 2, 4, 8, 8, 16, 5, 0, 12, 4, 4,
            rep(8, 8))
  for (i in seq_along(ok)) {
    p <- check_dict(npy_dict(sprintf("'%s'", ok[i]), "()"), raw(size[i]))
    expect_identical(p$descr, ok[i], info = ok[i])
    expect_identical(p$itemsize, size[i], info = ok[i])
  }
})

test_that("'a' is S, and U counts code points", {
  p <- check_dict(npy_dict("'|a3'", "(2,)"), raw(6))
  expect_identical(p$descr, "|S3")
  p <- check_dict(npy_dict("'<U3'", "(2,)"), raw(24))
  expect_identical(p$itemsize, 12)
})

test_that("'=' and a missing byte order read as little-endian, reported", {
  p <- check_dict(npy_dict("'=f8'"), raw(8))
  expect_identical(p$descr, "<f8")
  expect_true(p$native_order)
  p <- check_dict(npy_dict("'f8'"), raw(8))
  expect_true(p$native_order)
  p <- check_dict(npy_dict("'=u1'"), raw(1))
  expect_identical(p$descr, "|u1")
  expect_false(p$native_order)
})

test_that("shapes: scalar, vector, zero-length, Fortran order", {
  expect_identical(check_dict(npy_dict("'<i4'", "()"), raw(4))$shape, numeric())
  expect_identical(check_dict(npy_dict("'<i4'", "(0, 5)"))$count, 0)
  p <- check_dict(npy_dict("'<i4'", "(2, 3)", "True"), raw(24))
  expect_true(p$fortran_order)
})

test_that("the literal grammar is Python's, as far as headers need it", {
  # Double quotes, no trailing comma, other whitespace, key order.
  d <- '{"shape": (2,),"fortran_order":False,\t"descr": "<i2"}'
  expect_identical(check_dict(d, raw(4))$descr, "<i2")
  # A trailing comma inside the shape tuple and the dict.
  expect_identical(check_dict("{'descr': '<i2', 'fortran_order': False, 'shape': (1, 2,),}",
                         raw(4))$shape, c(1, 2))
  # (2) is 2 in parentheses, not a tuple; the fault is at the 2.
  d <- npy_dict("'<i2'", "(2)")
  e <- expect_zunpy_error(check_dict(d), "zunpy_parse_error")
  expect_identical(e$offset, 10 + as.double(regexpr("(2)", d, fixed = TRUE)))
})

test_that("16-byte alignment is accepted and reported", {
  p <- check_dict(npy_dict("'<f8'"), raw(8), align = 16L)
  expect_false(p$align64)
})

test_that("versions 2 and 3 have a 4-byte length; 3 is UTF-8", {
  p <- check_dict(npy_dict("'<f8'"), raw(8), version = 2L)
  expect_identical(p$version, c(2L, 0L))
  expect_identical(p$data_offset %% 64, 0)
  d <- "{'descr': [('é€', '<i4')], 'fortran_order': False, 'shape': (1,), }"
  p <- check_dict(d, raw(4), version = 3L)
  expect_identical(p$fields$name, "é€")
})

test_that("a Latin-1 header decodes its strings to UTF-8", {
  x <- npy_header_bytes(
    "{'descr': [('XX', '<i4')], 'fortran_order': False, 'shape': (1,), }",
    raw(4)
  )
  i <- which(x == charToRaw("X"))
  x[i] <- as.raw(c(0xe9, 0x41))
  expect_identical(znp_header_check(x)$fields$name, "éA")
})

test_that("string escapes decode", {
  d <- "{'descr': [('a\\'b\\\\c\\x41\\u00e9\\U0001F600', '<i4')], 'fortran_order': False, 'shape': (1,), }"
  expect_identical(check_dict(d, raw(4))$fields$name, "a'b\\cAé\U0001F600")
})

test_that("structured dtypes: list form, titles, padding, subarrays", {
  d <- paste0("{'descr': [(('T', 'a'), '<u4'), ('', '|V4'), ",
              "('b', '<f8', (3,)), ('c', '<U2'), ('', '<i2')], ",
              "'fortran_order': False, 'shape': (2,), }")
  p <- check_dict(d, raw(2 * 42))
  expect_identical(p$fields$name, c("a", "b", "c", "f4"))
  expect_identical(p$fields$title, c("T", NA, NA, NA))
  expect_identical(p$fields$descr, c("<u4", "<f8", "<U2", "<i2"))
  expect_identical(p$fields$offset, c(0, 8, 32, 40))
  expect_identical(p$fields$shape, list(numeric(), 3, numeric(), numeric()))
  expect_identical(p$itemsize, 42)
})

test_that("structured dtypes: the dict form with offsets and itemsize", {
  d <- paste0("{'descr': {'names': ['a', 'b'], 'formats': ['<i4', '<f8'], ",
              "'offsets': [0, 8], 'itemsize': 24, 'titles': [None, 'B'], ",
              "'aligned': True}, 'fortran_order': False, 'shape': (1,), }")
  p <- check_dict(d, raw(24))
  expect_identical(p$fields$offset, c(0, 8))
  expect_identical(p$fields$title, c(NA, "B"))
  expect_identical(p$itemsize, 24)
})

test_that("an empty record list is a zero-width record", {
  p <- check_dict("{'descr': [], 'fortran_order': False, 'shape': (3,), }")
  expect_identical(p$itemsize, 0)
  expect_identical(p$count, 3)
})
