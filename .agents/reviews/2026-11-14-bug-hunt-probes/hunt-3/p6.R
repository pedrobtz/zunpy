.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
df <- function(nm, n = 1) { d <- as.data.frame(matrix(1:(n*length(nm)), n)); names(d) <- nm; d }
for (L in 65300:65450) {
  writeBin(npy_encode(df(strrep("n", L))), sprintf("out6/hl_%d.npy", L))
  writeBin(npy_encode(df(paste0(strrep("n", L - 1), "€"))), sprintf("out6/hlu_%d.npy", L))
  writeBin(npy_encode(df(paste0(strrep("n", L - 1), "é"))), sprintf("out6/hll_%d.npy", L))
  writeBin(npy_encode(df(paste0(strrep("n", L - 1), " "))), sprintf("out6/hle_%d.npy", L))
}
# own reader on large headers
b <- npy_encode(df(paste0("f", 1:1024)))
print(tryCatch(dim(npy_decode(b)), error = function(e) conditionMessage(e)))
print(tryCatch(dim(npy_decode(b, max_header = 1e6)), error = function(e) conditionMessage(e)))
