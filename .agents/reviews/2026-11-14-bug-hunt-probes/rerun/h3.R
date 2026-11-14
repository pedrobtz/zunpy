.libPaths(c(Sys.getenv("HL"), .libPaths())); suppressMessages(library(zunpy))
source(file.path(Sys.getenv("HS"), "tests/testthat/helper-bytes.R"))
o <- Sys.getenv("HO")
dat <- function(b) { h <- npy_header(b); b[(h$data_offset + 1):length(b)] }
cat("H3-1 f2 1+2^-11+2^-40:", paste(dat(npy_encode(1 + 2^-11 + 2^-40, dtype = "<f2"))), "\n")
cat("H3-1 f2 2^-25*(1+2^-52):", paste(dat(npy_encode(2^-25 * (1 + 2^-52), dtype = "<f2"))), "\n")
bn <- "\xc3\xa9"; Encoding(bn) <- "bytes"
z <- tryCatch(npy_encode(setNames(list(1, 2), c("é", bn))), error = function(e) class(e)[1])
if (is.raw(z)) { writeBin(z, file.path(o, "dup.npz")); cat("H3-2 npz written; zunpy reads:", tryCatch(paste(npy_names(z)), error = function(e) class(e)[1]), "\n") } else cat("H3-2", z, "\n")
cat("H3-4 f4 1e300 ->", npy_decode(npy_encode(1e300, dtype = "<f4")), " c8:", format(npy_decode(npy_encode(complex(real = 1e300, imaginary = 1), dtype = "<c8"))), "\n")
x <- npy_header_bytes("{'descr': '<M8[ns]', 'fortran_order': False, 'shape': (1,), }", as.raw(c(rep(255, 7), 127)))
v <- npy_decode(x); cat("H3-6 M8[ns] max read", format(unclass(v), digits = 20), "; write back:", tryCatch({npy_encode(v, unit = "ns"); "ok"}, error = function(e) class(e)[1]), "\n")
m <- setNames(rep(list(raw()), 65535), sprintf("m%05d", 1:65535)); writeBin(npy_encode(m), file.path(o, "m65535.npz"))
