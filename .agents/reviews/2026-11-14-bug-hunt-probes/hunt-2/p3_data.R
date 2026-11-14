.libPaths(c("HUNT_ROOT/lib", .libPaths()))
suppressMessages(library(zunpy))
dir <- commandArgs(TRUE)[1]
t <- read.delim(file.path(dir, "man.tsv"), header = FALSE, colClasses = "character")
bad <- 0; n <- 0
chk <- function(v, i, how) {
  e <- file.path(dir, paste0(t$V1[i], ".exp")); eb <- readBin(e, "raw", file.size(e))
  shp <- as.integer(strsplit(t$V3[i], ",")[[1]])
  wantdim <- if (length(shp) >= 2) shp else NULL
  wanttype <- switch(t$V4[i], int = if (t$V5[i] == "lgl") "logical" else "integer", dbl = "double", cplx = "complex")
  got <- writeBin(as.vector(if (is.logical(v)) as.integer(v) else v), raw(), endian = "little")
  ok <- identical(got, eb) && identical(dim(v), wantdim) && typeof(v) == wanttype && length(setdiff(names(attributes(v)), "dim")) == 0 
  n <<- n + 1
  if (!ok) { bad <<- bad + 1; cat("MISMATCH", how, t$V1[i], t$V2[i], t$V3[i], typeof(v), "dim", dim(v), "\n") }
}
for (i in seq_len(nrow(t))) {
  f <- file.path(dir, paste0(t$V1[i], ".npy"))
  x <- readBin(f, "raw", file.size(f))
  for (how in c("decode", "read", "con", "decode2")) {
    v <- tryCatch(switch(how, decode = , decode2 = npy_decode(x), read = npy_read(f),
      con = { con <- rawConnection(x); on.exit(close(con)); r <- npy_read(con); close(con); on.exit(); r }),
      error = function(e) { cat("ERR", how, t$V1[i], t$V2[i], t$V3[i], conditionMessage(e), "\n"); NULL },
      warning = function(e) { cat("WARN", how, t$V1[i], t$V2[i], t$V3[i], conditionMessage(e), "\n"); NULL })
    if (!is.null(v)) chk(v, i, how)
  }
  # order = "file": dims reversed for C files, memory = file
  h <- npy_header(x)
  vf <- npy_decode(x, order = "file"); vff <- npy_read(f, order = "file")
  if (!identical(vf, vff)) cat("FILE-ORDER read/decode differ", t$V1[i], "\n")
  shp <- as.integer(strsplit(t$V3[i], ",")[[1]])
  wd <- if (length(shp) >= 2) (if (h$fortran_order) shp else rev(shp)) else NULL
  if (!identical(dim(vf), wd)) cat("FILE-ORDER dim", t$V1[i], t$V2[i], t$V3[i], dim(vf), "\n")
  if (!h$fortran_order && length(shp) >= 2) {
    if (!identical(as.vector(aperm(vf)), as.vector(npy_decode(x)))) cat("FILE-ORDER aperm", t$V1[i], "\n")
  }
}
cat("checked", n, "bad", bad, "\n")
