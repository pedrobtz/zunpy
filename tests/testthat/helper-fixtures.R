# NumPy-written fixtures (tools/make-fixtures.py) and the values their
# MANIFEST.tsv records for them.

fixture_path <- function(name) {
  testthat::test_path("fixtures", "npy", name)
}

fixture_bytes <- function(name) {
  path <- fixture_path(name)
  readBin(path, "raw", file.size(path))
}

fixtures_manifest <- function() {
  utils::read.delim(fixture_path("MANIFEST.tsv"), colClasses = "character",
                    quote = "", na.strings = character())
}

# A MANIFEST row's values as the R value npy_decode() should return, in R's
# index order (design section 6.4).
fixture_expected <- function(row) {
  if (grepl("@", row$values, fixed = TRUE) || startsWith(row$descr, "|V") &&
      !nzchar(row$values)) {
    return(fixture_records(row))
  }
  v <- strsplit(row$values, " ", fixed = TRUE)[[1]]
  kind <- substr(row$descr, 2, 2)
  width <- suppressWarnings(as.integer(substring(row$descr, 3)))
  hex_bytes <- function(t) {
    h <- substring(t, 3)
    if (!nzchar(h)) return(raw())
    as.raw(strtoi(substring(h, seq(1, nchar(h), 2), seq(2, nchar(h), 2)), 16L))
  }
  text <- function(t) {
    s <- rawToChar(hex_bytes(t))
    Encoding(s) <- "UTF-8"
    s
  }
  value <- switch(kind,
    S = , U = vapply(v, text, "", USE.NAMES = FALSE),
    V = lapply(v, hex_bytes),
    M = , m = fixture_time(v, row$descr),
    b = v == "True",
    i = , u = if (width <= 2 || (kind == "i" && width == 4)) {
      as.integer(v)
    } else {
      as.numeric(v)
    },
    f = as.numeric(v),
    c = {
      parts <- strsplit(v, ":", fixed = TRUE)
      complex(real = as.numeric(vapply(parts, `[`, "", 1)),
              imaginary = as.numeric(vapply(parts, `[`, "", 2)))
    }
  )
  shape <- if (nzchar(row$shape)) as.integer(strsplit(row$shape, ",")[[1]]) else integer()
  if (length(shape) < 2) {
    return(value)
  }
  # The values are listed in C order: fill the reversed shape, then turn it,
  # keeping the class (Date, POSIXct, difftime) aperm() drops.
  keep <- attributes(value)
  out <- aperm(array(unclass(value), rev(shape)), rev(seq_along(shape)))
  attributes(out) <- c(attributes(out), keep[setdiff(names(keep), "names")])
  out
}

# datetime64 and timedelta64 counts as npy_decode() classes them: the
# nearest double to count / scale, which R's division gives exactly for
# counts up to 2^53.
fixture_time <- function(v, descr) {
  kind <- substr(descr, 2, 2)
  unit <- sub("^.*\\[(.*)\\]$", "\\1", descr)
  count <- suppressWarnings(as.numeric(v))
  scale <- c(D = 1, s = 1, ms = 1e3, us = 1e6, ns = 1e9, m = 1, h = 1, W = 1)
  if (kind == "M" && unit == "D") return(structure(count, class = "Date"))
  if (kind == "M" && unit %in% c("s", "ms", "us", "ns")) {
    return(structure(count / scale[[unit]], class = c("POSIXct", "POSIXt"),
                     tzone = "UTC"))
  }
  if (kind == "m" && unit %in% names(scale)) {
    units <- switch(unit, D = "days", h = "hours", m = "mins", W = "weeks", "secs")
    return(structure(count / scale[[unit]], class = "difftime", units = units))
  }
  NULL  # integer64: compared separately
}

# A structured fixture as npy_decode() returns it: a data frame with a
# column per segment of the MANIFEST row, rows in R's order, and npy_shape
# when the array is not 1-d.
fixture_records <- function(row) {
  shape <- if (nzchar(row$shape)) as.integer(strsplit(row$shape, ",")[[1]]) else integer()
  n <- prod(shape)
  segments <- if (nzchar(row$values)) strsplit(row$values, " | ", fixed = TRUE)[[1]] else character()
  # The C-order index of each row in R's (column-major) order.
  perm <- if (length(shape) >= 2) {
    as.vector(aperm(array(seq_len(n), rev(shape)), rev(seq_along(shape))))
  } else {
    seq_len(n)
  }
  cols <- list()
  for (seg in segments) {
    head <- sub(" .*$", "", seg)
    parts <- strsplit(head, "@", fixed = TRUE)[[1]]
    name <- rawToChar(as.raw(strtoi(substring(parts[2], seq(1, nchar(parts[2]), 2),
                                             seq(2, nchar(parts[2]), 2)), 16L)))
    Encoding(name) <- "UTF-8"
    values <- if (grepl(" ", seg, fixed = TRUE)) sub("^[^ ]* ", "", seg) else ""
    col <- fixture_expected(list(descr = parts[3], shape = as.character(n),
                                 values = values))
    cols[[name]] <- if (length(dim(col)) == 0) col[perm] else col
  }
  df <- structure(cols, class = "data.frame", row.names = c(NA_integer_, -n))
  if (length(shape) != 1L) attr(df, "npy_shape") <- as.numeric(shape)
  df
}

# The dtypes of design section 6.1, the third copy of its table
# (test-tables.R keeps the three in step).
table_dtypes <- function() {
  c("b1", "i1", "i2", "i4", "i8", "u1", "u2", "u4", "u8", "f2", "f4", "f8",
    "c8", "c16", "S", "U", "V", "M8", "m8")
}
