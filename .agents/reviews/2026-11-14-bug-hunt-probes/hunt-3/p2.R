.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
set.seed(1)
# halves: random f16 midpoints +/- tiny
e <- sample(-26:15, 20000, TRUE); m <- sample(0:2047, 20000, TRUE)
base <- (1 + (m + 0.5)/1024/2*2) * 2^e   # includes exact f16 values and midpoints
base <- (1024 + m/2) / 1024 * 2^e          # m odd -> midpoint between halves
eps <- sample(c(0, 1, -1, 2^10, -2^10, 2^28, -2^28, 2^29, 2^30,-2^30), 20000, TRUE)
x <- base * (1 + eps * 2^-52)
x <- c(x, -x, 65519.999999999, 65520*(1-2^-53), 65520, 2^-25, 2^-25*(1+2^-52), 2^-25*(1-2^-53), 3*2^-25, 3*2^-25*(1-2^-53),3*2^-25*(1+2^-52))
x <- x[abs(x) < 65520]
writeBin(npy_encode(x), "out2/f2_src.npy"); writeBin(npy_encode(x, dtype="<f2"), "out2/f2.npy")
# f4
e <- sample(-152:127, 20000, TRUE); m <- sample(0:(2^24-1), 20000, TRUE)
base <- (2^23 + m/2) / 2^23 * 2^e
eps <- sample(c(0, 1, -1, 2, -2, 2^20), 20000, TRUE)
y <- base * (1 + eps * 2^-52); y <- c(y, -y)
writeBin(npy_encode(y), "out2/f4_src.npy"); writeBin(npy_encode(y, dtype="<f4"), "out2/f4.npy")
z <- complex(real = y, imaginary = rev(y))
writeBin(npy_encode(z), "out2/c8_src.npy"); writeBin(npy_encode(z, dtype="<c8"), "out2/c8.npy")
# NaN payloads
nan <- c(NaN, NA_real_, -NaN, readBin(as.raw(c(1,0,0,0,0,0,0xf0,0x7f)), "double"), readBin(as.raw(c(0,0,0,0,0,0,0xf4,0xff)), "double"),readBin(as.raw(c(0,0,0,0,0x20,0,0xf0,0x7f)), "double"))
writeBin(npy_encode(nan), "out2/nan_src.npy"); writeBin(npy_encode(nan, dtype="<f4"), "out2/nan_f4.npy"); writeBin(npy_encode(nan, dtype="<f2"), "out2/nan_f2.npy")
writeBin(npy_encode(complex(real=nan, imaginary=rev(nan)), dtype="<c8"), "out2/nan_c8.npy")
for (v in c(1e300, -1e300, 1e39)) for (d in c("<f4","<f2")) cat(v, d, tryCatch(paste(npy_decode(npy_encode(v, dtype=d))), error=function(e) conditionMessage(e)), "\n")
cat(tryCatch(paste(npy_decode(npy_encode(complex(real=1e300,imaginary=1), dtype="<c8"))), error=function(e) conditionMessage(e)), "\n")
r <- withCallingHandlers(npy_encode(c(TRUE,NA), na="allow", dtype="<i4"), warning=function(w) cat("WARN:", conditionMessage(w), "\n"))
r <- withCallingHandlers(npy_encode(c(TRUE,NA), na="allow", dtype="<f8"), warning=function(w) cat("WARN:", conditionMessage(w), "\n"))
r <- withCallingHandlers(npy_encode(c(TRUE,NA), na="allow", dtype="<i8"), warning=function(w) cat("WARN:", conditionMessage(w), "\n"), error=function(e) cat("ERR", conditionMessage(e), "\n"))
