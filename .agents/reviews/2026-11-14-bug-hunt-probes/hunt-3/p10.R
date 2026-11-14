.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
sur <- rawToChar(as.raw(c(0x61, 0xed, 0xa0, 0x80))); Encoding(sur) <- "UTF-8"
print(validUTF8(sur))
t <- function(label, expr) { r <- tryCatch(expr, error = function(e) paste("ERR", class(e)[1], conditionMessage(e))); cat(label, ":", if (is.raw(r)) paste("WRITTEN", length(r)) else r, "\n"); invisible(r) }
t("U surrogate", npy_encode(sur))
r <- t("S surrogate", npy_encode(sur, dtype = "|S"))
r <- t("field surrogate", npy_encode(setNames(data.frame(1), sur)))
r <- t("npz surrogate", npy_encode(setNames(list(1), sur))); if (is.raw(r)) writeBin(r, "out10/sur.npz")
over <- rawToChar(as.raw(c(0xf4, 0x90, 0x80, 0x80))); Encoding(over) <- "UTF-8"; print(validUTF8(over))
r <- t("npz >10FFFF", npy_encode(setNames(list(1), over))); if (is.raw(r)) writeBin(r, "out10/over.npz")
ol <- rawToChar(as.raw(c(0xc0, 0xaf))); Encoding(ol) <- "UTF-8"; print(validUTF8(ol))
r <- t("npz overlong slash", npy_encode(setNames(list(1), ol))); if (is.raw(r)) writeBin(r, "out10/overlong.npz")
r <- t("field overlong", npy_encode(setNames(data.frame(1), ol)))
t("U overlong", npy_encode(ol))
# NUL/odd names
r <- t("npz name newline", npy_encode(setNames(list(1), "a\nb"))); if (is.raw(r)) writeBin(r, "out10/nl.npz")
r <- t("npz name only spaces", npy_encode(setNames(list(1), " "))); 
r <- t("npz name trailing dot", npy_encode(setNames(list(1), "..")))
r <- t("npz name ' ..'", npy_encode(setNames(list(1), "a..b")))
r <- t("npz name NA", npy_encode(setNames(list(1), NA)))
r <- t("npz name dup case", npy_encode(list(a = 1, A = 2)))
r <- t("npz name a and a.npy", npy_encode(setNames(list(1, 2), c("a", "a.npy")))); if (is.raw(r)) writeBin(r, "out10/anpy.npz")
# member raising warnings: lgl NA allow in npz
r <- withCallingHandlers(npy_encode(list(a = c(TRUE, NA), b = c(NA, NA)), na = "allow"), warning = function(w) { cat("WARN", conditionMessage(w), "\n"); invokeRestart("muffleWarning") })
# args pass-through to members
b <- npy_encode(list(m = matrix(1:6, 2), t = as.POSIXct(1.5, origin = "1970-01-01"), s = "é"), order = "C", unit = "ms", encoding = "latin1", dtype = list(s = "|S"))
x <- npy_decode(b); str(x); print(npy_header(npy_encode(matrix(1:6, 2), order = "C"))$fortran_order)
writeBin(b, "out10/args.npz")
