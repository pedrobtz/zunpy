.libPaths(c(Sys.getenv("HL"), .libPaths())); suppressMessages(library(zunpy))
source(file.path(Sys.getenv("HS"), "tests/testthat/helper-bytes.R"))
g <- file.path(Sys.getenv("HH"), "hunt-2/p21_wrong.npy.gz")
a <- npy_read(g); b <- npy_read(gzfile(g))
cat("H2-F1 path==gzfile:", identical(a, b), " len", length(a), length(b), " head", format(head(a,2)), "|", format(head(b,2)), "\n")
# H2-F3: EOCD count smaller than the directory
z <- npy_encode(list(a = 1L, b = 2L, c = 3L)); at <- find_bytes(z, as.raw(c(0x50,0x4b,0x05,0x06)))
stopifnot(length(at) == 1); z2 <- z; z2[at + 8] <- as.raw(2); z2[at + 10] <- as.raw(2)
cat("H2-F3 names:", paste(npy_names(z2), collapse = ","), " decode:", paste(names(npy_decode(z2)), collapse = ","), "\n")
writeBin(z2, file.path(Sys.getenv("HO"), "eocd2.npz"))
# H2-F5: npy_names reads the whole connection
f <- tempfile(fileext = ".npz"); npy_write(list(a = numeric(1e5), b = 1:3), f)
con <- file(f, "rb"); n <- npy_names(con); rest <- length(readBin(con, "raw", 1e7)); close(con)
cat("H2-F5 names", n, "bytes left on con", rest, "of", file.size(f), " | max_size=size-1:", tryCatch({npy_names(f, max_size = file.size(f) - 1); "ok"}, error = function(e) class(e)[1]), "\n")
# H2-F6
x <- npy_header_bytes("{'descr': '|u1', 'fortran_order': False, 'shape': (0, 9007199254740993), }")
cat("H2-F6 shape", format(npy_header(x)$shape, scientific = FALSE), "\n")
# H2-F7 u4 integer64
y <- npy_header_bytes("{'descr': '<u4', 'fortran_order': False, 'shape': (1,), }", as.raw(c(255,255,255,255)))
cat("H2-F7 u4 int64 class", class(npy_decode(y, int64 = "integer64")), "\n")
# H2-F4: zero-width S0 huge count -> base error?
s <- npy_header_bytes("{'descr': '|S0', 'fortran_order': False, 'shape': (2147483648,), }")
e <- tryCatch(npy_decode(s), error = function(e) e); cat("H2-F4 S0 2^31 class:", class(e)[1], "\n")
u <- npy_header_bytes("{'descr': '<U536870912', 'fortran_order': False, 'shape': (0,), }")
gc(reset = TRUE); r <- npy_decode(u); m <- gc(); cat("H2-F4 U536870912 x0 -> length", length(r), " max used MB", m[2, 6], "\n")
