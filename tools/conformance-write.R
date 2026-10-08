# The R side of the writing conformance check (design section 15, roadmap
# Stage 3): writes one .npy per R value of design section 7.1 with the
# installed zunpy, and a MANIFEST.tsv in the format of
# tools/make-fixtures.py, for tools/conformance.py to check against
# np.load(). Usage: Rscript tools/conformance-write.R DIR
library(zunpy)
out <- commandArgs(TRUE)[1]
dir.create(out, showWarnings = FALSE, recursive = TRUE)

hex <- function(r) paste(sprintf("%02x", as.integer(r)), collapse = "")

show <- function(v, descr = "") {
  kind <- substr(descr, 2, 2)
  if (kind == "U") {
    return(vapply(enc2utf8(v), function(s) paste0("s:", hex(charToRaw(s))), "",
                  USE.NAMES = FALSE))
  }
  if (kind == "S") {
    return(vapply(v, function(s) paste0("b:", hex(charToRaw(s))), "",
                  USE.NAMES = FALSE))
  }
  if (kind %in% c("M", "m")) {
    return(ifelse(is.na(v), "NaT", format(v, scientific = FALSE, trim = TRUE)))
  }
  if (is.logical(v)) return(ifelse(v, "True", "False"))
  if (is.complex(v)) return(paste0(show(Re(v)), ":", show(Im(v))))
  if (is.integer(v)) return(as.character(v))
  s <- sprintf("%a", v)
  s[is.nan(v) | is.na(v)] <- "nan"
  s[v == Inf] <- "inf"
  s[v == -Inf] <- "-inf"
  s
}

# The values in C (row-major) order, NumPy's logical order.
c_order <- function(x) {
  if (length(dim(x)) < 2) return(as.vector(x))
  as.vector(aperm(x, rev(seq_along(dim(x)))))
}

values <- list(
  logical = c(TRUE, FALSE, TRUE),
  integer = c(-.Machine$integer.max, 0L, 7L, .Machine$integer.max),
  double = c(0, -0, 1.5, -2.25, Inf, -Inf, NaN, NA, .Machine$double.xmax, 5e-324),
  complex = complex(real = c(1.5, -0, Inf), imaginary = c(NaN, 2, -1)),
  matrix = matrix(seq(0.5, 6, by = 0.5), 3),
  array = array(1:24, c(2, 3, 4)),
  empty = matrix(numeric(), 0, 3),
  narrow_f4 = c(1 + 2^-30, 3.4e38, 1e-46),
  narrow_f2 = c(65504, 1e-8, 0.1),
  narrow_u2 = c(0L, 65535L),
  unicode = matrix(c("", "a", "h\u00e9llo", "\u65e5\u672c", "\U0001F600x", "t q"), 2),
  bytes = c("abc", "", "h\u00e9"),
  date = as.Date(c("1970-01-01", "2024-10-08", NA, "1900-03-01")),
  posix_us = as.POSIXct(c("2024-10-08 12:00:00.123456", NA, "1960-01-01"), tz = "UTC"),
  posix_ns = as.POSIXct(c("1970-01-01 00:00:01.5", "1969-12-31 23:59:59"), tz = "UTC"),
  hours = as.difftime(c(1, 25, NA), units = "hours"),
  millis = as.difftime(c(1.5, -0.001), units = "secs")
)
dtypes <- list(narrow_f4 = "<f4", narrow_f2 = "<f2", narrow_u2 = "<u2",
               bytes = "|S", posix_ns = "<M8[ns]", millis = "<m8[ms]")

rows <- character()
for (name in names(values)) {
  x <- values[[name]]
  for (order in c("F", "C")) {
    file <- sprintf("r-%s-%s.npy", name, tolower(order))
    bytes <- npy_encode(x, dtype = dtypes[[name]], order = order)
    writeBin(bytes, file.path(out, file))
    h <- npy_header(bytes)
    # The expected values are what the file holds: R's value, narrowed to
    # the dtype the way npy_decode() reads it back.
    expected <- npy_decode(bytes)
    if (substr(h$descr, 2, 2) %in% c("M", "m")) {
      # The counts in the file, as NumPy's int64 view shows them: R's value
      # times the ticks per R unit, exact for the counts below 2^53 used here.
      unit <- sub("^.*\\[(.*)\\]$", "\\1", h$descr)
      scale <- c(ms = 1e3, us = 1e6, ns = 1e9)[unit]
      if (is.na(scale)) scale <- 1
      expected <- round(as.numeric(expected) * scale)
    }
    rows <- c(rows, paste(
      file, h$descr, paste(h$shape, collapse = ","),
      if (h$fortran_order) "F" else "C", "R", "-",
      paste(show(c_order(expected), h$descr), collapse = " "), sep = "\t"
    ))
  }
}
# A data frame as a record array (roadmap Stage 5): one segment per column,
# "@<hex of the name>@<descr>" and its values, as tools/make-fixtures.py
# writes structured fixtures.
df <- data.frame(
  id = c(1L, -2L, 3L), x = c(0.5, NA, -Inf), s = c("a", "h\u00e9", ""),
  d = as.Date(c("2024-10-08", NA, "1970-01-01")), b = c(TRUE, FALSE, TRUE),
  stringsAsFactors = FALSE
)
names(df)[5] <- "caf\u00e9"
bytes <- npy_encode(df)
writeBin(bytes, file.path(out, "r-records.npy"))
h <- npy_header(bytes)
back <- npy_decode(bytes)
segments <- vapply(seq_along(back), function(j) {
  descr <- h$descr$descr[j]
  values <- back[[j]]
  if (substr(descr, 2, 2) == "M") values <- as.numeric(values)
  paste(c(paste0("@", hex(charToRaw(enc2utf8(names(back)[j]))), "@", descr),
          show(values, descr)), collapse = " ")
}, "")
rows <- c(rows, paste("r-records.npy", "|V", nrow(df), "C", "R", "-",
                      paste(segments, collapse = " | "), sep = "\t"))

# A .npz, stored and compressed (roadmap Stage 6): each member also written
# on its own, so that np.load() of the archive can be compared with it.
arch <- list(m = values$matrix, s = values$unicode, r = df)
for (z in c(FALSE, TRUE)) {
  file <- if (z) "r-archive-deflate.npz" else "r-archive.npz"
  writeBin(npy_encode(arch, compress = z), file.path(out, file))
  pairs <- character()
  for (k in names(arch)) {
    single <- sprintf("r-archive-%s.npy", k)
    writeBin(npy_encode(arch[[k]]), file.path(out, single))
    pairs <- c(pairs, paste0(k, "=", single))
  }
  rows <- c(rows, paste(file, "npz", "", "", "R", "-", paste(pairs, collapse = " "),
                        sep = "\t"))
}

writeLines(c("file\tdescr\tshape\torder\tnumpy\tsha256\tvalues", rows),
           file.path(out, "MANIFEST.tsv"))
cat(length(rows), "files written to", out, "\n")
