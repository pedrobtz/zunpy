source("lib.R")
i4 <- function(v) le(as.integer(v), 4)
hd <- H("'<i4'", "(2,)")
f <- tempfile(fileext = ".npy")
three <- function(label, x, ...) {
  r1 <- try1(npy_decode(x, ...)); writeBin(x, f); r2 <- try1(npy_read(f, ...)); con <- rawConnection(x); r3 <- try1(npy_read(con, ...)); close(con)
  r4 <- try1(npy_header(x)); r5 <- try1(npy_header(f)); con <- rawConnection(x); r6 <- try1(npy_header(con)); close(con)
  d <- function(r) if (r$ok) paste0("OK ", paste(format(r$v), collapse = ","), if (!is.null(dim(r$v))) paste0(" dim ", paste(dim(r$v), collapse = "x")), if (length(r$w)) paste0(" [", paste(sub("zunpy_", "", r$w), collapse = ","), "]")) else paste0(sub("zunpy_", "", r$cls), "@", format(r$e$offset), if (length(r$w)) paste0(" [", paste(sub("zunpy_", "", r$w), collapse = ","), "]"))
  h <- function(r) if (r$ok) paste0("OK v", r$v$version, " off ", r$v$data_offset, if (length(r$w)) paste0(" [", paste(sub("zunpy_", "", r$w), collapse = ","), "]")) else paste0(sub("zunpy_", "", r$cls), "@", format(r$e$offset))
  same <- identical(d(r1), d(r2)) && identical(d(r1), d(r3)) && identical(r1$v, r2$v) && identical(r1$v, r3$v)
  sameh <- identical(h(r4), h(r5)) && identical(h(r4), h(r6))
  cat(sprintf("%-30s %s %s\n", label, d(r1), if (same) "" else paste0("  !! path: ", d(r2), " | con: ", d(r3))))
  cat(sprintf("%-30s   hdr: %s %s\n", "", h(r4), if (sameh) "" else paste0("  !! path: ", h(r5), " | con: ", h(r6))))
}
x <- mk(hd, i4(1:2))
three("v1 align64", x)
three("v1 align16", mk(hd, i4(1:2), align = 16))
three("v1 align 1 (pad 0)", mk(hd, i4(1:2), pad = 0))
three("v1 align 8", mk(hd, i4(1:2), pad = 3 + 8))
three("v1 align 32", mk(hd, i4(1:2), align = 32))
three("v2", mk(hd, i4(1:2), ver = 2L)); three("v3", mk(hd, i4(1:2), ver = 3L)); three("v2 align16", mk(hd, i4(1:2), ver = 2L, align = 16))
for (v in list(c(0, 0), c(4, 0), c(1, 1), c(2, 1), c(3, 5), c(255, 0))) { y <- x; y[7:8] <- as.raw(v); three(paste("version", v[1], v[2]), y) }
for (k in c(0, 1, 5, 6, 7, 8, 9, 10, 11, 12, 20)) three(paste("first", k, "bytes"), x[seq_len(k)])
y <- x; y[1] <- as.raw(0x92); three("magic byte0", y); y <- x; y[6] <- as.raw(0x5a); three("magic byte5", y)
three("data truncated 1", x[-length(x)]); three("data trailing 1", c(x, as.raw(0))); three("header only (no data)", x[1:128])
y <- x; y[9:10] <- as.raw(c(0xff, 0xff)); three("hlen 65535 > file", y)
y <- mk(hd, i4(1:2), ver = 2L); y[9:12] <- as.raw(c(0xff, 0xff, 0xff, 0xff)); three("v2 hlen 2^32-1", y); three("v2 hlen 2^32-1 mh", y, max_header = 2^32 - 1)
y <- mk(hd, i4(1:2), ver = 2L); y[9:12] <- as.raw(c(0x74, 0, 0, 0x80)); three("v2 hlen 2^31+116", y)
y <- x; y[9:10] <- as.raw(c(6, 0)); three("hlen 6 (cuts dict)", y[1:16])
three("hlen 0", c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0, 0, 0)), raw(6)))
# big v1 header: exactly 65535? data offset must be %16: 10+len -> len=65526
bigpad <- 65526 - nchar(hd) - 1
three("v1 hlen 65526 mh def", mk(hd, i4(1:2), pad = bigpad)); three("v1 hlen 65526 mh 65526", mk(hd, i4(1:2), pad = bigpad), max_header = 65526)
three("v2 hlen 70004", mk(hd, i4(1:2), ver = 2L, pad = 70004 - nchar(hd) - 1), max_header = 70004)
three("default mh 10000 at 9990", mk(hd, i4(1:2), pad = 9990 - nchar(hd) - 1)); three("default mh at 10006", mk(hd, i4(1:2), pad = 10006 - nchar(hd) - 1))
cat("== header text encodings\n")
hr <- function(s) as.raw(s)
d1 <- c(charToRaw("{'descr': [('"), as.raw(0xe9), charToRaw("', '<i4')], 'fortran_order': False, 'shape': (2,), }"))
d3 <- c(charToRaw("{'descr': [('"), as.raw(c(0xc3, 0xa9)), charToRaw("', '<i4')], 'fortran_order': False, 'shape': (2,), }"))
for (v in 1:3) { r <- try1(npy_decode(mk(raw_hdr = d1, data = i4(1:2), ver = v))); cat("latin1 byte, v", v, ":", if (r$ok) paste(encodeString(names(r$v)), Encoding(names(r$v))) else paste(r$cls, r$e$offset), "\n")
                 r <- try1(npy_decode(mk(raw_hdr = d3, data = i4(1:2), ver = v))); cat("utf8 bytes, v", v, ":", if (r$ok) paste(encodeString(names(r$v)), Encoding(names(r$v))) else paste(r$cls, r$e$offset), "\n") }
for (b in c(0x00, 0x01, 0x7f, 0x80, 0x9f, 0xa0, 0xff)) { d <- c(charToRaw("{'descr': [('a"), as.raw(b), charToRaw("', '<i4')], 'fortran_order': False, 'shape': (2,), }"))
  r <- try1(npy_decode(mk(raw_hdr = d, data = i4(1:2)))); cat(sprintf("v1 name byte 0x%02x: %s\n", b, if (r$ok) paste(encodeString(names(r$v)), paste(charToRaw(names(r$v)), collapse = "")) else paste(r$cls, r$e$offset))) }
# NUL / high byte outside a string, in padding
d <- c(charToRaw(hd), as.raw(0)); r <- try1(npy_decode(mk(raw_hdr = d, data = i4(1:2)))); cat("NUL after dict:", if (r$ok) "OK" else paste(r$cls, r$e$offset), "\n")
d <- c(charToRaw(hd), as.raw(0xa0)); r <- try1(npy_decode(mk(raw_hdr = d, data = i4(1:2)))); cat("NBSP after dict:", if (r$ok) "OK" else paste(r$cls, r$e$offset), "\n")
for (e in c("\\x00", "\\0", "\\u0000", "\\ud800", "\\U00110000", "\\xe9", "\\u00e9", "\\N{DIGIT ONE}", "\\a", "\\q", "\\\n")) {
  r <- try1(npy_decode(mk(H(sprintf("[('a%s', '<i4')]", e), "(2,)"), i4(1:2)))); cat(sprintf("escape %-12s: %s\n", encodeString(e), if (r$ok) paste(encodeString(names(r$v)), paste(charToRaw(names(r$v)), collapse = "")) else paste(r$cls, r$e$offset))) }
