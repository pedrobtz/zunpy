# A .npy laid out as NumPy lays it out, for tools/fuzz-seeds.R and
# tools/mutation-cases.R. tests/testthat/helper-bytes.R has the same
# builder for the test suite.
npy_header_bytes <- function(dict, data = raw(), version = 1L, align = 64L,
                             len = NULL) {
  dict <- charToRaw(enc2utf8(dict))
  prefix_len <- if (version == 1L) 10L else 12L
  total <- prefix_len + length(dict) + 1L
  pad <- (align - total %% align) %% align
  header <- c(dict, rep(as.raw(0x20), pad), as.raw(0x0a))
  n <- if (is.null(len)) length(header) else len
  len_bytes <- if (version == 1L) {
    as.raw(c(n %% 256, n %/% 256))
  } else {
    as.raw(c(n %% 256, (n %/% 256) %% 256, (n %/% 65536) %% 256,
             n %/% 16777216))
  }
  c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59)), as.raw(c(version, 0L)),
    len_bytes, header, data)
}

npy_dict <- function(descr, shape = "(1,)", fortran = "False") {
  sprintf("{'descr': %s, 'fortran_order': %s, 'shape': %s, }",
          descr, fortran, shape)
}

le <- function(value, width) {
  out <- raw(width)
  for (i in seq_len(width)) {
    out[i] <- as.raw(value %% 256)
    value <- value %/% 256
  }
  out
}

# A stored ZIP of the members given (a named list of raw vectors), plain
# 32-bit records; CRCs are left 0, which the directory check does not read.
zip_bytes <- function(members) {
  body <- raw()
  central <- raw()
  for (nm in names(members)) {
    data <- members[[nm]]
    name <- charToRaw(nm)
    offset <- length(body)
    body <- c(body, le(0x04034b50, 4), le(20, 2), le(0, 2), le(0, 2), le(0, 2),
              le(0x21, 2), le(0, 4), le(length(data), 4), le(length(data), 4),
              le(length(name), 2), le(0, 2), name, data)
    central <- c(central, le(0x02014b50, 4), le(20, 2), le(20, 2), le(0, 2),
                 le(0, 2), le(0, 2), le(0x21, 2), le(0, 4), le(length(data), 4),
                 le(length(data), 4), le(length(name), 2), le(0, 2), le(0, 2),
                 le(0, 2), le(0, 2), le(0, 4), le(offset, 4), name)
  }
  c(body, central, le(0x06054b50, 4), le(0, 2), le(0, 2),
    le(length(members), 2), le(length(members), 2), le(length(central), 4),
    le(length(body), 4), le(0, 2))
}
