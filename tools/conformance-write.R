# The R side of the writing conformance check (design section 15, roadmap
# Stage 3): writes one .npy per R value of design section 7.1 with the
# installed zunpy, and a MANIFEST.tsv in the format of
# tools/make-fixtures.py, for tools/conformance.py to check against
# np.load(). Usage: Rscript tools/conformance-write.R DIR
library(zunpy)
out <- commandArgs(TRUE)[1]
dir.create(out, showWarnings = FALSE, recursive = TRUE)

show <- function(v) {
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
  narrow_u2 = c(0L, 65535L)
)
dtypes <- list(narrow_f4 = "<f4", narrow_f2 = "<f2", narrow_u2 = "<u2")

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
    rows <- c(rows, paste(
      file, h$descr, paste(h$shape, collapse = ","),
      if (h$fortran_order) "F" else "C", "R", "-",
      paste(show(c_order(expected)), collapse = " "), sep = "\t"
    ))
  }
}
writeLines(c("file\tdescr\tshape\torder\tnumpy\tsha256\tvalues", rows),
           file.path(out, "MANIFEST.tsv"))
cat(length(rows), "files written to", out, "\n")
