# Hostile headers (design sections 12 and 15), each a permanent regression,
# and one test per GUARD in src/znp_header.c. tools/run-mutation-check
# proves each guard load-bearing through fuzz/probe.c; these tests prove the
# R path reports it with the right class and fields.

test_that("GUARD declared-size: a shape of (2**40, 2**40) costs nothing", {
  x <- npy_header_bytes(npy_dict("'<f8'", "(1099511627776, 1099511627776)"))
  e <- expect_zunpy_error(znp_header_check(x), "zunpy_size_limit")
  expect_identical(e$limit, "max_size")
})

test_that("GUARD dims: 33 dimensions are refused by default", {
  shape <- paste0("(", paste(rep("1", 33), collapse = ", "), ")")
  x <- npy_header_bytes(npy_dict("'|u1'", shape), raw(1))
  e <- expect_zunpy_error(znp_header_check(x), "zunpy_dims_limit")
  expect_identical(e$limit_value, 32)
  expect_identical(znp_header_check(x, max_dims = 64)$count, 1)
})

test_that("GUARD header-limit: a 10,001-byte header is refused", {
  x <- npy_header_bytes(npy_dict("'<f8'"), raw(8), version = 2L, len = 10001)
  e <- expect_zunpy_error(znp_header_check(x), "zunpy_header_limit")
  expect_identical(e$limit_value, 10000)
})

test_that("GUARD depth: a list nested 9 deep is refused", {
  nested <- paste0(strrep("[", 8), strrep("]", 8))
  x <- npy_header_bytes(sprintf("{'descr': '<f8', 'fortran_order': False, 'shape': (), 'x': %s}",
                   nested), raw(8))
  e <- expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")
  expect_gt(e$offset, 10)
})

test_that("malformed descr strings are parse errors", {
  for (d in c("'<i3'", "'|f8'", "'<b1'", "'<U'", "'<M8[x]'", "'<M8'",
              "'>i1'", "'<S3'", "'|U2'", "'<f8 '", "'<x8'", "''", "'<M8[ns'")) {
    e <- expect_zunpy_error(znp_header_check(npy_header_bytes(npy_dict(d), raw(8))), "zunpy_parse_error")
    expect_identical(e$offset, 10 + 10, info = d)
  }
})

test_that("object, long double and nested records are unsupported", {
  for (d in c("|O", "|O8", "<f16", "<c32", "<f12")) {
    e <- expect_zunpy_error(
      znp_header_check(npy_header_bytes(npy_dict(sprintf("'%s'", d)), raw(8))),
      "zunpy_unsupported_type"
    )
    expect_identical(e$dtype, d)
  }
  x <- npy_header_bytes("{'descr': [('a', [('b', '<i4')])], 'fortran_order': False, 'shape': (1,), }",
           raw(4))
  expect_zunpy_error(znp_header_check(x), "zunpy_unsupported_type")
})

test_that("GUARD duplicate-key and a missing or unknown key", {
  d <- "{'descr': '<f8', 'descr': '<f8', 'fortran_order': False, 'shape': (), }"
  expect_zunpy_error(znp_header_check(npy_header_bytes(d, raw(8))), "zunpy_parse_error")
  expect_zunpy_error(znp_header_check(npy_header_bytes("{'descr': '<f8', 'shape': (), }", raw(8))),
                     "zunpy_parse_error")
  d <- "{'descr': '<f8', 'fortran_order': False, 'shape': (), 'x': 1}"
  expect_zunpy_error(znp_header_check(npy_header_bytes(d, raw(8))), "zunpy_parse_error")
})

test_that("GUARD key-type: a key that is not a string", {
  d <- "{'descr': '<f8', 'fortran_order': False, 'shape': (), 1: 2}"
  expect_zunpy_error(znp_header_check(npy_header_bytes(d, raw(8))), "zunpy_parse_error")
})

test_that("values of the wrong type are parse errors", {
  for (d in c(
    "{'descr': 8, 'fortran_order': False, 'shape': (), }",
    "{'descr': '<f8', 'fortran_order': 0, 'shape': (), }",
    "{'descr': '<f8', 'fortran_order': False, 'shape': [1], }",
    "{'descr': '<f8', 'fortran_order': False, 'shape': ('1',), }",
    "{'descr': '<f8', 'fortran_order': False, 'shape': (1.0,), }",
    "['descr', '<f8']"
  )) {
    expect_zunpy_error(znp_header_check(npy_header_bytes(d, raw(8))), "zunpy_parse_error")
  }
})

test_that("GUARD negative-dim: negative and oversized dimensions", {
  expect_zunpy_error(znp_header_check(npy_header_bytes(npy_dict("'<f8'", "(-1,)"))), "zunpy_parse_error")
  expect_zunpy_error(znp_header_check(npy_header_bytes(npy_dict("'<f8'", "(99999999999999999999,)"))),
                     "zunpy_parse_error")
})

test_that("the grammar has no identifiers, arithmetic or calls", {
  for (d in c(
    "{'descr': '<f8', 'fortran_order': false, 'shape': (), }",
    "{'descr': '<f8', 'fortran_order': False, 'shape': (1+1,), }",
    "{'descr': '<f8', 'fortran_order': False, 'shape': (len('a'),), }",
    "{'descr': '<f8', 'fortran_order': Falsey, 'shape': (), }",
    "{'descr': '<f8', 'fortran_order': False, 'shape': (01,), }",
    "{'descr': '<f8' 'fortran_order': False, 'shape': (), }",
    "{'descr': '<f8', 'fortran_order': False, 'shape': (),, }",
    "{'descr': '<\\q8', 'fortran_order': False, 'shape': (), }",
    "{'descr': '<f8', 'fortran_order': False, 'shape': (), } x"
  )) {
    expect_zunpy_error(znp_header_check(npy_header_bytes(d, raw(8))), "zunpy_parse_error")
  }
})

test_that("NUL is refused in a header string, escaped or not", {
  d <- "{'descr': [('a\\x00', '<i4')], 'fortran_order': False, 'shape': (1,), }"
  expect_zunpy_error(znp_header_check(npy_header_bytes(d, raw(4))), "zunpy_parse_error")
  x <- npy_header_bytes("{'descr': [('aZ', '<i4')], 'fortran_order': False, 'shape': (1,), }",
           raw(4))
  x[which(x == charToRaw("Z"))] <- as.raw(0)
  expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")
})

test_that("version 3 headers must be valid UTF-8", {
  x <- npy_header_bytes("{'descr': [('aZ', '<i4')], 'fortran_order': False, 'shape': (1,), }",
           raw(4), version = 3L)
  x[which(x == charToRaw("Z"))] <- as.raw(0xff)
  expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")
})

test_that("the prefix: magic, version, alignment", {
  good <- npy_header_bytes(npy_dict("'<f8'"), raw(8))
  x <- good; x[2] <- as.raw(0x4f)
  e <- expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")
  expect_identical(e$offset, 1)
  x <- good; x[7] <- as.raw(4)
  expect_identical(expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")$offset, 6)
  x <- good; x[8] <- as.raw(1)
  expect_identical(expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")$offset, 7)
  x <- npy_header_bytes(npy_dict("'<f8'"), raw(8), align = 8L)
  expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")
})

test_that("GUARD header-truncated and every proper prefix is truncation", {
  x <- npy_header_bytes(npy_dict("'<i2'", "(3,)"), as.raw(1:6))
  for (n in 0:(length(x) - 1)) {
    e <- expect_zunpy_error(znp_header_check(x[seq_len(n)]), "zunpy_parse_error")
    expect_true(n == 0 || e$offset <= n, info = n)
  }
  # The length field claims more header than there is.
  x <- npy_header_bytes(npy_dict("'<f8'"), raw(8), len = 200)
  expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")
})

test_that("GUARD data-truncated and GUARD trailing", {
  x <- npy_header_bytes(npy_dict("'<f8'", "(2,)"), raw(15))
  e <- expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")
  expect_identical(e$offset, as.double(length(x)))
  x <- npy_header_bytes(npy_dict("'<f8'", "(2,)"), raw(17))
  e <- expect_zunpy_error(znp_header_check(x), "zunpy_parse_error")
  expect_identical(e$offset, as.double(length(x) - 1))
})

test_that("GUARD input-size: max_size bounds the whole input", {
  x <- npy_header_bytes(npy_dict("'<f8'", "(2,)"), raw(16))
  e <- expect_zunpy_error(znp_header_check(x, max_size = length(x) - 1), "zunpy_size_limit")
  expect_identical(e$limit_value, length(x) - 1)
  expect_identical(znp_header_check(x, max_size = length(x))$count, 2)
})

test_that("GUARD zero-width: elements without bytes are bounded too", {
  x <- npy_header_bytes(npy_dict("'|S0'", "(1099511627776,)"))
  expect_zunpy_error(znp_header_check(x), "zunpy_size_limit")
  x <- npy_header_bytes("{'descr': [], 'fortran_order': False, 'shape': (1099511627776,), }")
  expect_zunpy_error(znp_header_check(x), "zunpy_size_limit")
})

test_that("GUARD fields: max_fields, in the list and the dict form", {
  fields <- paste(sprintf("('f%d', '|u1')", 1:3), collapse = ", ")
  x <- npy_header_bytes(sprintf("{'descr': [%s], 'fortran_order': False, 'shape': (1,), }",
                   fields), raw(3))
  e <- expect_zunpy_error(znp_header_check(x, max_fields = 2), "zunpy_limit_error")
  expect_identical(e$limit, "max_fields")
  expect_identical(nrow(as.data.frame(znp_header_check(x)$fields[1:4])), 3L)
  x <- npy_header_bytes(paste0("{'descr': {'names': ['a', 'b', 'c'], 'formats': ['|u1', '|u1', '|u1']}, ",
                  "'fortran_order': False, 'shape': (1,), }"), raw(3))
  expect_zunpy_error(znp_header_check(x, max_fields = 2), "zunpy_limit_error")
})

test_that("GUARD duplicate-field: field names are unique", {
  x <- npy_header_bytes("{'descr': [('a', '|u1'), ('a', '|u1')], 'fortran_order': False, 'shape': (1,), }",
           raw(2))
  expect_zunpy_error(znp_header_check(x), "zunpy_invalid_error")
})

test_that("GUARD overlap and GUARD field-past-itemsize in the dict form", {
  x <- npy_header_bytes(paste0("{'descr': {'names': ['a', 'b'], 'formats': ['<i4', '<i4'], ",
                  "'offsets': [0, 2]}, 'fortran_order': False, 'shape': (1,), }"),
           raw(6))
  expect_zunpy_error(znp_header_check(x), "zunpy_invalid_error")
  x <- npy_header_bytes(paste0("{'descr': {'names': ['a'], 'formats': ['<i4'], ",
                  "'offsets': [4], 'itemsize': 6}, 'fortran_order': False, 'shape': (1,), }"),
           raw(6))
  expect_zunpy_error(znp_header_check(x), "zunpy_invalid_error")
})

test_that("limits are checked as arguments", {
  x <- npy_header_bytes(npy_dict("'<f8'"), raw(8))
  e <- expect_zunpy_error(znp_header_check(x, max_dims = 65), "zunpy_invalid_argument")
  expect_identical(e$arg, "max_dims")
  expect_zunpy_error(znp_header_check(x, max_size = -1), "zunpy_invalid_argument")
  expect_zunpy_error(znp_header_check(x, max_header = NA), "zunpy_invalid_argument")
  expect_zunpy_error(znp_header_check(1:3), "zunpy_invalid_argument")
})

test_that("GUARD itemsize: no element larger than max_size, even with none", {
  x <- npy_header_bytes(npy_dict("'<U1000000000'", "(0,)"))
  e <- expect_zunpy_error(znp_header_check(x), "zunpy_size_limit")
  expect_identical(e$limit, "max_size")
  # Found by the fuzzer: a subarray shape that saturates the itemsize, with
  # no records to need the bytes.
  x <- npy_header_bytes(paste0(
    "{'descr': [('b', '<f8', (3, 6666666666666666666))], ",
    "'fortran_order': False, 'shape': (0,), }"
  ))
  expect_zunpy_error(znp_header_check(x), "zunpy_limit_error")
})

test_that("GUARD itemsize holds whatever max_size is", {
  # Found by the fuzzer with no size limit: fields whose sizes saturate.
  x <- npy_header_bytes(paste0(
    "{'descr': [('a', '<U3', (1,)), ('b', '<U4444444444', (3,)), ",
    "('c', '<U444444444444444444', (3, 4))], 'fortran_order': False, 'shape': (0,), }"
  ))
  expect_zunpy_error(znp_header_check(x, max_size = 2^53), "zunpy_size_limit")
})

test_that("GUARD columns: subarray elements count against max_fields", {
  d <- "{'descr': [('a', '|u1', (3,)), ('b', '|u1')], 'fortran_order': False, 'shape': (1,), }"
  x <- npy_header_bytes(d, raw(4))
  e <- expect_zunpy_error(znp_header_check(x, max_fields = 3), "zunpy_limit_error")
  expect_identical(e$limit, "max_fields")
  expect_identical(znp_header_check(x, max_fields = 4)$itemsize, 4)
  x <- npy_header_bytes(
    "{'descr': [('a', '|V0', (1073741824,))], 'fortran_order': False, 'shape': (1,), }"
  )
  expect_zunpy_error(znp_header_check(x), "zunpy_limit_error")
})
