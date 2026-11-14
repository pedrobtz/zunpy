.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
cat("locale:", Sys.getlocale("LC_CTYPE"), "\n")
print(as.character(npy_encode(1 + 2^-11 + 2^-40, dtype = "<f2")[-(1:128)]))   # numpy: 013c
print(npy_decode(npy_encode(2^-25 * (1 + 2^-52), dtype = "<f2")))               # numpy: 5.96e-08
x <- rawToChar(as.raw(c(0x68, 0xc3, 0xa9)))   # "hé" as UTF-8 bytes, encoding unknown (as readLines gives)
cat("Encoding:", Encoding(x), "\n")
print(npy_decode(npy_encode(x)))
print(npy_header(npy_encode(setNames(data.frame(1), x)))$descr)
print(npy_names(npy_encode(setNames(list(1), x))))
print(npy_decode(npy_encode(x, dtype = "|S"), strings = "raw"))
