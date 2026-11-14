.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
for (u in c("s","ms","us","ns")) {
  x <- npy_read(sprintf("out4/in_%s.npy", u)); stopifnot(inherits(x, "POSIXct"))
  r <- tryCatch(npy_encode(x, unit = u), error = function(e) {cat(u, conditionMessage(e), "\n"); NULL})
  if (!is.null(r)) writeBin(r, sprintf("out4/in_%s.out.npy", u))
  x <- npy_read(sprintf("out4/ind_%s.npy", u)); stopifnot(inherits(x, "difftime"))
  r <- tryCatch(npy_encode(x, dtype = sprintf("<m8[%s]", u)), error = function(e) {cat("d", u, conditionMessage(e), "\n"); NULL})
  if (!is.null(r)) writeBin(r, sprintf("out4/ind_%s.out.npy", u))
}
for (n in c("bigns", "bigus")) {
  x <- npy_read(sprintf("out4/in_%s.npy", n))
  r <- tryCatch(npy_encode(x, unit = substr(n, 4, 5)), error = function(e) {cat(n, conditionMessage(e), "\n"); NULL})
  if (!is.null(r)) writeBin(r, sprintf("out4/in_%s.out.npy", n))
}
# round trip of big s
x <- structure(c(2^53, 2^53+2, -2^53-2), class = c("POSIXct", "POSIXt"))
b <- npy_encode(x, unit = "s"); print(tryCatch(npy_decode(b), error=function(e) conditionMessage(e)))
print(tryCatch(npy_decode(npy_encode(as.difftime(2^53+2, units="secs"))), error=function(e) conditionMessage(e)))
print(tryCatch(npy_decode(npy_encode(structure(2^53+2, class="Date"))), error=function(e) conditionMessage(e)))
