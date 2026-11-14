source("lib.R")
dir <- commandArgs(TRUE)[1]
t <- read.delim(file.path(dir, "man.tsv"), header = FALSE, quote = "", colClasses = "character", encoding = "UTF-8")
fmt <- function(v) paste(vapply(names(v), function(k) paste0(k, "=[", paste(format(as.vector(v[[k]])), collapse = ", "), "]"), ""), collapse = " ; ")
for (i in seq_len(nrow(t))) {
  f <- file.path(dir, paste0(t$V1[i], ".npz"))
  x <- readBin(f, "raw", file.size(f))
  r <- try1(npy_decode(x)); r2 <- try1(npy_read(f)); r3 <- try1(npy_names(x)); r4 <- try1(npy_names(f))
  con <- file(f, "rb"); r5 <- try1(npy_read(con)); close(con)
  s <- if (r$ok) paste("OK", if (length(r$v) > 20) paste(length(r$v), "members; first", fmt(r$v[1:2]), "last", fmt(r$v[length(r$v)])) else fmt(r$v)) else paste("ERR", r$cls, r$msg)
  np <- t$V2[i]; if (nchar(np) > 300) np <- paste(substr(np, 1, 150), "...", substr(np, nchar(np) - 60, nchar(np)))
  cat(sprintf("%-22s\n   np: %s\n   zu: %s %s\n   names: %s | same(read path)=%s same(con)=%s same(names path)=%s\n", t$V1[i], np, s, paste(r$w, collapse = ","),
      if (r3$ok) paste(utils::head(r3$v, 6), collapse = ",") else paste("ERR", r3$cls, r3$msg),
      identical(r$v, r2$v) && identical(r$ok, r2$ok), identical(r$v, r5$v) && identical(r$ok, r5$ok), identical(r3$v, r4$v)))
}
