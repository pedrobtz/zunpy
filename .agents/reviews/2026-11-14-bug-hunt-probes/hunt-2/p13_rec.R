source("lib.R"); suppressMessages(library(bit64))
dir <- commandArgs(TRUE)[1]
t <- read.delim(file.path(dir, "man.tsv"), header = FALSE, quote = "", colClasses = "character", encoding = "UTF-8", sep = "\t")
bad <- 0; n <- 0
for (i in seq_len(nrow(t))) {
  f <- file.path(dir, paste0(t$V1[i], ".npy"))
  x <- readBin(f, "raw", file.size(f))
  r <- try1(npy_decode(x))
  if (!r$ok) { cat("ERR", t$V1[i], t$V2[i], t$V3[i], r$cls, r$msg, "\n"); bad <- bad + 1; next }
  if (length(r$w)) cat("WARN", t$V1[i], t$V2[i], r$w, "\n")
  v <- r$v; n <- n + 1
  want <- enc2utf8(strsplit(t$V5[i], "\x1f", fixed = TRUE)[[1]])
  shp <- as.numeric(strsplit(t$V3[i], ",")[[1]])
  ok <- is.data.frame(v) && identical(names(v), want) && nrow(v) == (if (length(shp)) prod(shp) else 1) &&
        identical(attr(v, "npy_shape"), if (length(shp) == 1) NULL else shp)
  if (!ok) { cat("STRUCT MISMATCH", t$V1[i], t$V2[i], t$V3[i], "| names:", encodeString(names(v)), "| want:", encodeString(want), "| nrow", nrow(v), "| npy_shape", attr(v, "npy_shape"), "\n"); bad <- bad + 1; next }
  for (j in seq_along(want)) {
    e <- npy_read(file.path(dir, sprintf("%s_c%02d.npy", t$V1[i], j - 1)))
    if (!identical(v[[j]], e)) { cat("COL MISMATCH", t$V1[i], t$V2[i], t$V3[i], "F" , t$V4[i], want[j], "\n"); print(utils::head(v[[j]])); print(utils::head(e)); bad <- bad + 1 }
  }
  # order = "file": rows in file order, npy_shape reversed for C files
  vf <- npy_decode(x, order = "file"); vp <- npy_read(f); 
  if (!identical(vp, v)) { cat("READ != DECODE", t$V1[i], "\n"); bad <- bad + 1 }
  h <- npy_header(x)
  if (length(shp) >= 2 && !h$fortran_order) {
    if (!identical(attr(vf, "npy_shape"), rev(shp))) { cat("FILE npy_shape", t$V1[i], attr(vf, "npy_shape"), "\n"); bad <- bad + 1 }
    idx <- as.vector(aperm(array(seq_len(prod(shp)), rev(shp))))
    for (j in seq_along(want)) if (!identical(vf[[j]][idx], v[[j]]) && prod(shp) > 0) { cat("FILE order rows", t$V1[i], want[j], "\n"); bad <- bad + 1 }
  } else if (!identical(vf, v)) { cat("FILE != R for F/1-d", t$V1[i], "\n"); bad <- bad + 1 }
}
cat("files ok-ish", n, "bad", bad, "\n")
