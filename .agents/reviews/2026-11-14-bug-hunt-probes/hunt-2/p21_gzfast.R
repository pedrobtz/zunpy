# A gzip-compressed .npy whose on-disk size equals the size its (decompressed) header declares:
# the direct path of npy_read() reads the header through file() + open("rb") (which auto-decompresses)
# and the data through file(path, "rb") (which does not): the raw compressed bytes come back as numbers.
source("lib.R")
set.seed(42)
d <- tempfile(); dir.create(d); g <- file.path(d, "x.npy.gz")
rd <- function(n) readBin(as.raw(sample(0:255, 8 * n, TRUE)), "double", n)     # incompressible doubles
put <- function(v) { con <- gzfile(g, "wb"); writeBin(npy_encode(v), con); close(con); file.size(g) - (128 + 8 * length(v)) }
for (n in c(100, 1000, 5000, 20000, 40000)) cat("n", n, "compressed - raw =", put(rd(n)), "\n")
hit <- NULL; t0 <- Sys.time()
for (try in 1:3000) {
  v <- c(rd(sample(20:1500, 1)), rep(0, sample(0:3, 1)))
  if (put(v) == 0) { hit <- v; break }
  if (difftime(Sys.time(), t0, units = "secs") > 80) break
}
cat("tries", try, "hit:", !is.null(hit), "\n")
if (!is.null(hit)) {
  v <- hit; x <- npy_encode(v)
  cat("on-disk bytes:", file.size(g), " npy bytes:", length(x), "\n")
  r <- try1(npy_read(g)); cat("npy_read(path):", if (r$ok) "returns a value, no error" else paste(r$cls, r$msg), "| warnings:", length(r$w), "\n")
  cat("identical to the array that was written:", identical(r$v, v), "\n")
  cat("written  :", format(utils::head(v, 4), digits = 6), "\n"); cat("returned :", format(utils::head(r$v, 4), digits = 6), "\n")
  con <- gzfile(g); r2 <- try1(npy_read(con)); cat("npy_read(gzfile(path)) identical to written:", identical(r2$v, v), "\n")
  r3 <- try1(npy_decode(readBin(g, "raw", file.size(g)))); cat("npy_decode(bytes on disk):", r3$cls, r3$msg, "\n")
  file.copy(g, "p21_wrong.npy.gz", overwrite = TRUE)
}
