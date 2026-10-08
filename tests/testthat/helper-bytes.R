# Bytes for tests, built by hand so that every case says what it is.

# A raw vector from hex, spaces allowed: bytes("93 4e 55").
bytes <- function(hex) {
  hex <- gsub("[^0-9a-fA-F]", "", hex)
  as.raw(strtoi(substring(hex, seq(1, nchar(hex), 2), seq(2, nchar(hex), 2)),
                16L))
}

# A whole .npy as NumPy lays it out: magic, version, little-endian header
# length, the dict, spaces to a multiple of `align`, a newline, then data.
# `dict` is the header text exactly; `len` overrides the length field.
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

# The dict NumPy writes for a plain array.
npy_dict <- function(descr, shape = "(1,)", fortran = "False") {
  sprintf("{'descr': %s, 'fortran_order': %s, 'shape': %s, }",
          descr, fortran, shape)
}

# The check phase over a header built from `dict`.
check_dict <- function(dict, data = raw(), ...) {
  znp_header_check(npy_header_bytes(dict, data, ...))
}

# The 0-based offsets where a 4-byte little-endian signature starts.
find_sig <- function(x, sig) {
  b <- as.raw(c(sig %% 256, (sig %/% 256) %% 256, (sig %/% 65536) %% 256,
                sig %/% 16777216))
  n <- length(x) - 3
  if (n < 1) return(integer())
  which(x[1:n] == b[1] & x[2:(n + 1)] == b[2] & x[3:(n + 2)] == b[3] &
          x[4:(n + 3)] == b[4]) - 1L
}

# Writes a little-endian unsigned value of `width` bytes at a 0-based offset.
put_le <- function(x, offset, value, width) {
  for (i in seq_len(width)) {
    x[offset + i] <- as.raw(value %% 256)
    value <- value %/% 256
  }
  x
}
