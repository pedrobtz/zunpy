.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
for (n in c("bigns", "bigus")) {
  x <- npy_read(sprintf("out4/in_%s.npy", n))
  ok <- vapply(seq_along(x), function(i) !inherits(try(npy_encode(x[i], unit = substr(n, 4, 5)), silent = TRUE), "try-error"), NA)
  cat(n, "refused:", which(!ok), "\n")
  i64 <- npy_read(sprintf("out4/in_%s.npy", n), datetime = "integer64")
  print(i64[!ok]); print(format(as.numeric(x[!ok]), digits = 22))
  writeBin(npy_encode(x[ok], unit = substr(n, 4, 5)), sprintf("out4/in_%s.out.npy", n))
  writeBin(npy_encode(i64[ok]), sprintf("out4/in_%s.keep.npy", n))
}
