# The performance targets of design section 16, measured. Not a CI gate;
# results are recorded in the design. Usage: tools/run-benchmarks [n]
library(zunpy)
n <- as.numeric(commandArgs(TRUE)[1])
if (is.na(n)) n <- 1e7
reps <- 5

time <- function(expr) {
  expr <- substitute(expr)
  env <- parent.frame()
  t <- vapply(seq_len(reps), function(i) {
    gc()
    system.time(eval(expr, env))[["elapsed"]]
  }, 0)
  median(t)
}

row <- function(what, zunpy, base) {
  cat(sprintf("%-44s %8.3f s %8.3f s %6.2fx\n", what, zunpy, base, zunpy / base))
}

cat(sprintf("zunpy %s, R %s, %s, n = %s, median of %d\n",
            zunpy_info()$version, getRversion(), R.version$platform,
            format(n, big.mark = ","), reps))
cat(sprintf("%-44s %10s %10s %7s\n", "", "zunpy", "base R", "ratio"))

d <- as.double(seq_len(n))
i <- as.integer(seq_len(n) %% 1e6)
bd <- npy_encode(d)
bi <- npy_encode(i)
hd <- npy_header(bd)$data_offset
row("decode f8 (raw -> double)", time(npy_decode(bd)),
    time(readBin(bd[-seq_len(hd)], "double", n, 8)))
row("decode i4 (raw -> integer)", time(npy_decode(bi)),
    time(readBin(bi[-seq_len(hd)], "integer", n, 4)))
row("encode f8 (double -> raw)", time(npy_encode(d)), time(writeBin(d, raw())))
row("encode i4 (integer -> raw)", time(npy_encode(i)), time(writeBin(i, raw())))

m <- matrix(d, ncol = 100)
bc <- npy_encode(m, order = "C")
row("decode f8 matrix, C order (one permutation)", time(npy_decode(bc)),
    time(readBin(bc[-seq_len(hd)], "double", n, 8)))

f <- tempfile(fileext = ".npy")
g <- tempfile()
row("npy_write / writeBin to a file", time(npy_write(d, f)),
    time(writeBin(d, g)))
row("npy_read / readBin from a file", time(npy_read(f)),
    time(readBin(g, "double", n)))

s <- sprintf("w%07d", seq_len(n / 10))
bs <- npy_encode(s)
row(sprintf("decode U8 (%s strings)", format(n / 10, big.mark = ",")),
    time(npy_decode(bs)),
    time(iconv(rawToChar(bs[-seq_len(npy_header(bs)$data_offset)], multiple = TRUE),
               "UCS-4LE", "UTF-8")))

z <- tempfile(fileext = ".npz")
row("npy_write .npz stored / writeBin", time(npy_write(list(d = d), z)),
    time(writeBin(d, g)))
row("npy_read .npz stored / readBin", time(npy_read(z)), time(readBin(g, "double", n)))
unlink(c(f, g, z))

if (requireNamespace("RcppCNPy", quietly = TRUE)) {
  h <- tempfile(fileext = ".npy")
  RcppCNPy::npySave(h, d)
  row("RcppCNPy::npyLoad / npy_read", time(RcppCNPy::npyLoad(h)), time(npy_read(h)))
  unlink(h)
} else {
  cat("RcppCNPy is not installed; its row is skipped\n")
}
