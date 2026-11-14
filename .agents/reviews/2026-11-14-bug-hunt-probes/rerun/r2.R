.libPaths(c(Sys.getenv("HL"), .libPaths())); suppressMessages(library(zunpy))
source(file.path(Sys.getenv("HS"), "tests/testthat/helper-bytes.R"))
# F2: big-endian M8[h]
x <- npy_header_bytes("{'descr': '>M8[h]', 'fortran_order': False, 'shape': (2,), }", as.raw(c(0,0,0,0,0,0,0,5, 0,0,0,0,0,0,0,7)))
v <- npy_decode(x); cat("F2 class", class(v), "npy_dtype", attr(v, "npy_dtype"), "\n")
cat("F2 rewritten", npy_header(npy_encode(v))$descr, " npy_dtype()", npy_dtype(v), "\n")
# F3: 0-d structured
y <- npy_header_bytes("{'descr': [('a', '<i4')], 'fortran_order': False, 'shape': (), }", as.raw(c(7,0,0,0)))
r <- npy_decode(y); str(attributes(r)$npy_shape)
cat("F3", tryCatch({npy_encode(r); "encoded"}, error = function(e) paste(class(e)[1], conditionMessage(e))), "\n")
# F4: gz path
f <- tempfile(fileext = ".npy.gz"); con <- gzfile(f, "wb"); writeBin(npy_encode(as.double(1:1000)), con); close(con)
cat("F4 header", npy_header(f)$shape, "\n")
cat("F4 path", tryCatch(length(npy_read(f)), error = function(e) class(e)[1]), " conn", length(npy_read(file(f))), "\n")
# F5
cat("F5", npy_dtype(c("a","bbb")), "vs", npy_header(npy_encode(c("a","bbb")))$descr, "\n")
cat("F5 df", tryCatch(npy_dtype(data.frame(a = 1)), error = function(e) class(e)[1]), "\n")
# F6
z <- npy_encode(list(a = 1:3, "a.npy" = "x")); zf <- file.path(Sys.getenv("HO"), "l.npz"); writeBin(z, zf)
cat("F6 zunpy", paste(npy_names(z), collapse = ","), "\n")
