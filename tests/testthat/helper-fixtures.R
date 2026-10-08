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
  v <- strsplit(row$values, " ", fixed = TRUE)[[1]]
  kind <- substr(row$descr, 2, 2)
  width <- as.integer(substring(row$descr, 3))
  value <- switch(kind,
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
  # The values are listed in C order: fill the reversed shape, then turn it.
  aperm(array(value, rev(shape)), rev(seq_along(shape)))
}
