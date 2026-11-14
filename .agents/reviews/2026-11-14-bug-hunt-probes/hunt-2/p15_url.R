source("lib.R")
port <- commandArgs(TRUE)[1]
x <- npy_encode(matrix(as.numeric(1:600), 20)); writeBin(x, "p15/m.npy")
u8 <- npy_encode(as.raw(1:200)); writeBin(u8, "p15/u.npy")
z <- npy_encode(list(a = 1:300, b = c(2.5, 3.5)), compress = TRUE); writeBin(z, "p15/z.npz")
for (mode in c("len", "nolen", "short")) for (nm in c("m.npy", "u.npy", "z.npz", "missing.npy")) {
  u <- sprintf("http://127.0.0.1:%s/%s/%s", port, mode, nm)
  r <- try1(npy_read(u)); want <- switch(nm, m.npy = npy_decode(x), u.npy = npy_decode(u8), z.npz = npy_decode(z), NULL)
  cat(sprintf("%-6s %-12s read: %s", mode, nm, if (r$ok) paste("OK identical:", identical(r$v, want)) else paste(r$cls, substr(r$msg, 1, 80))), if (length(r$w)) paste("[warn", paste(r$w, collapse = ","), "]"), "\n")
  if (nm != "z.npz") { r <- try1(npy_header(u)); cat(sprintf("%-6s %-12s header: %s\n", mode, nm, if (r$ok) paste("OK", paste(r$v$shape, collapse = "x")) else paste(r$cls, substr(r$msg, 1, 80)))) }
  else { r <- try1(npy_names(u)); cat(sprintf("%-6s %-12s names: %s\n", mode, nm, if (r$ok) paste(r$v, collapse = ",") else paste(r$cls, substr(r$msg, 1, 80)))) }
}
u <- sprintf("HTTP://127.0.0.1:%s/len/m.npy", port); r <- try1(npy_read(u)); cat("uppercase scheme:", if (r$ok) "OK" else paste(r$cls, r$msg), "\n")
u <- sprintf("http://127.0.0.1:%s/len/m.npy", port); r <- try1(npy_read(u, max_size = length(x) - 1)); cat("url max_size-1:", r$cls, r$msg, "\n")
r <- try1(npy_read(u, max_size = length(x))); cat("url max_size exact:", r$ok, "\n")
r <- try1(npy_read(u, names = "a")); cat("url names on npy:", r$cls, "\n")
p <- pipe("cat p15/m.npy"); r <- try1(npy_read(p)); cat("pipe:", if (r$ok) identical(r$v, npy_decode(x)) else paste(r$cls, r$msg), "\n")
p <- pipe("cat p15/z.npz", "rb"); r <- try1(npy_read(p)); close(p); cat("pipe open npz:", if (r$ok) identical(r$v, npy_decode(z)) else paste(r$cls, r$msg), "\n")
# connection positioned mid-stream: read from current position
con <- file("p15/both.bin", "wb"); writeBin(c(as.raw(1:7), x), con); close(con)
con <- file("p15/both.bin", "rb"); invisible(readBin(con, "raw", 7)); r <- try1(npy_read(con)); cat("open con at offset 7:", if (r$ok) identical(r$v, npy_decode(x)) else paste(r$cls, r$msg), "\n"); close(con)
# two arrays back to back on one connection
con <- file("p15/two.bin", "wb"); writeBin(c(x, u8), con); close(con)
con <- file("p15/two.bin", "rb"); r <- try1(npy_read(con)); cat("two arrays on one connection:", if (r$ok) "OK" else paste(r$cls, r$msg), "\n"); close(con)
con <- file("p15/two.bin", "rb"); r <- try1(npy_header(con)); r2 <- try1(readBin(con, "raw", 4)); cat("npy_header(con) then position: header ok", r$ok, "next bytes", format(r2$v), " (data starts", format(x[129:132]), ")\n"); close(con)
tc <- textConnection("abc"); r <- try1(npy_read(tc)); cat("text connection:", r$cls, r$msg, "\n"); close(tc)
con <- file("p15/m.npy", "r"); r <- try1(npy_read(con)); cat("file opened 'r' (text):", r$cls, r$msg, "\n"); close(con)
for (bad in list(NULL, NA, 1, character(), c("a", "b"), "", "p15", "p15/nope.npy", list(), TRUE, raw(4))) { r <- try1(npy_read(bad)); cat("file =", deparse(bad), "->", if (r$ok) "OK" else paste(r$cls, substr(r$msg, 1, 70)), "\n") }
