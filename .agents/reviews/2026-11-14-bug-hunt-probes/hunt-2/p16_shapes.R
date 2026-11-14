source("lib.R"); suppressMessages(library(bit64))
dir <- commandArgs(TRUE)[1]
t <- read.delim(file.path(dir, "man.tsv"), header = FALSE, colClasses = "character")
bad <- 0
for (i in seq_len(nrow(t))) {
  f <- file.path(dir, paste0(t$V1[i], ".npy")); x <- readBin(f, "raw", file.size(f))
  shp <- as.integer(strsplit(t$V3[i], ",")[[1]])
  for (how in c("decode", "read")) {
    r <- try1(if (how == "decode") npy_decode(x) else npy_read(f))
    e <- npy_read(file.path(dir, paste0(t$V1[i], "_e.npy")))
    if (!r$ok) { cat("ERR", t$V1[i], t$V2[i], t$V3[i], r$cls, r$msg, "\n"); bad <- bad + 1; next }
    v <- r$v; wd <- if (length(shp) >= 2) shp else NULL
    a1 <- attributes(v); a1$dim <- NULL; if (!length(a1)) a1 <- NULL; a2 <- attributes(e)
    flat <- v; dim(flat) <- NULL
    if (!identical(dim(v), wd) || !identical(a1[sort(names(a1))], a2[sort(names(a2))]) || !identical(unclass(as.vector(unclass(flat))), unclass(as.vector(unclass(e))))) {
      cat("MISMATCH", how, t$V1[i], t$V2[i], "shape", t$V3[i], "F", t$V4[i], "| dim", dim(v), "| attrs", names(attributes(v)), "/", names(attributes(e)), "\n"); bad <- bad + 1 }
  }
}
cat("n", nrow(t), "bad", bad, "\n")
