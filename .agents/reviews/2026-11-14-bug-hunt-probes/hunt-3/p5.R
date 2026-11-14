.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
w <- function(.n, x, ...) {
  r <- tryCatch(npy_encode(x, ...), error = function(e) { cat(.n, "ERR:", conditionMessage(e), "\n"); NULL })
  if (!is.null(r)) writeBin(r, file.path("out5", paste0(.n, ".npy")))
  invisible(r)
}
df <- function(nm, n = 2) { d <- as.data.frame(matrix(1:(n*length(nm)), n)); names(d) <- nm; d }
names_list <- c("a", "it's", 'say "hi"', "both ' and \"", "back\\slash", "tab\there", "nl\nx", "cr\rx", "bell\ax", "del\x7fx",
  "nbsp x", "shy­x", "café", "ÿ", "\u0080", "\u009f", "¡", "€", "\U0001F600", "sp ace", " lead", "", "x,y", "(p)", "[b]", "{c}", "#", "Ā", "​", " ", "͸", "﻿", "µ", "×", "\x01", "\x1f", "é", "　", "\U000E0001", "퟿","", "؀", "؜"," ", "᠎", " ", " "," ", "⁠", "￹","￿", "\U0001D173", "\U00010000","\U0010FFFF", " ", "­")
for (i in seq_along(names_list)) w(sprintf("nm_%02d", i), df(names_list[i]))
writeLines(vapply(names_list, function(s) paste(sprintf("%d", utf8ToInt(s)), collapse = " "), ""), "out5/names.txt")
w("multi", data.frame(i = 1:3, d = c(1.5, NA, 3), l = c(TRUE, FALSE, TRUE), s = c("a", "bb", "€€€"), c = complex(real = 1:3, imaginary = -1), r = as.raw(1:3), dt = as.Date(c(0, 1, NA)), px = as.POSIXct(c(0, 1.5, NA), tz = "UTC", origin = "1970-01-01"), td = as.difftime(c(1, 2, NA), units = "mins"), f = factor(c("u", "v", "u")), stringsAsFactors = FALSE))
w("multi_dtype", data.frame(i = 1:3, d = c(1.5, 2, 3), s = c("a", "bb", "c")), dtype = c(i = "|u1", d = "<f4", s = "|S4"))
w("zero_rows", data.frame(a = integer(0), s = character(0)))
w("zero_cols", data.frame())
w("zero_cols_3rows", data.frame(row.names = 1:3))
w("dup", setNames(data.frame(1, 2), c("a", "a")))
w("lat_then_wide", df(c("café", "€")))
w("lat2", df(c("café", "üñ")))
d <- data.frame(a = 1:6, b = letters[1:6]); attr(d, "npy_shape") <- c(2, 3); w("shape23", d); w("shape23C", d, order = "C")
attr(d, "npy_shape") <- c(6, 1); w("shape61", d); attr(d, "npy_shape") <- c(1, 6); w("shape16", d)
attr(d, "npy_shape") <- c(2L, 3L); w("shape23int", d)
attr(d, "npy_shape") <- c(1, 2, 3, 1); w("shape1231", d); w("shape1231C", d, order="C")
d0 <- data.frame(a = integer(0)); attr(d0, "npy_shape") <- c(0, 5); w("shape05", d0); attr(d0, "npy_shape") <- c(5, 0); w("shape50", d0)
# column count
w("c1024", df(paste0("f", 1:1024), 1)); w("c1025", df(paste0("f", 1:1025), 1))
# header length boundary: one field with long name. dict = {'descr': [('NAME', '<i4')], 'fortran_order': False, 'shape': (1,), }+20 spaces
for (L in c(65440:65470)) w(sprintf("hl_%d", L), df(strrep("n", L), 1))
for (L in c(65440:65470)) w(sprintf("hlu_%d", L), df(paste0(strrep("n", L - 1), "€"), 1))
for (L in c(65440:65470)) w(sprintf("hll_%d", L), df(paste0(strrep("n", L - 1), "é"), 1))
# error mid-way
r <- tryCatch(npy_encode(data.frame(a = 1:3, b = c(1, 2, 3), c = c(1, 300, 3)), dtype = c(c = "|u1")), error = function(e) print(e))
r <- tryCatch(npy_encode(data.frame(a = 1:3, c = c(1L, NA, 3L))), error = function(e) print(e))
r <- tryCatch(npy_encode(data.frame(a = 1:3, c = c("a", NA, "b"))), error = function(e) print(e))
r <- tryCatch(npy_encode(data.frame(a = 1:3, c = c(1, 2, 3)), dtype = c(zz = "|u1")), error = function(e) print(e))
r <- tryCatch(npy_encode(data.frame(a = 1:3, c = c(1, 2, 3)), dtype = "|u1"), error = function(e) print(e))
r <- tryCatch(npy_encode(data.frame(a = 1:3, c = c(1, 2, 3)), dtype = c(a = NA_character_)), error = function(e) print(e))
x <- data.frame(a = 1:2); x$m <- matrix(1:4, 2); r <- tryCatch(npy_encode(x), error = function(e) print(e))
x <- data.frame(a = 1:2); x$m <- I(list(1, 2)); r <- tryCatch(npy_encode(x), error = function(e) print(e))
x <- data.frame(a = 1:2); x$m <- matrix(1:2, 2); r <- tryCatch(npy_encode(x), error = function(e) print(e)); if (is.raw(r)) writeBin(r, "out5/onecolmat.npy")
x <- data.frame(a = 1:2); x$d <- data.frame(q = 1:2); r <- tryCatch(npy_encode(x), error = function(e) print(e))
tb <- structure(list(a = 1:2, b = c("x", "y")), class = c("tbl_df", "tbl", "data.frame"), row.names = 1:2); w("tibble", tb)
