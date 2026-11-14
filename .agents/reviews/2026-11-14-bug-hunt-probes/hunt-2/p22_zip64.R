source("lib.R"); source("ziplib.R")
A <- npy_encode(1:3); B <- npy_encode(c(1.5, 2.5))
ex <- function(...) { b <- unlist(lapply(list(...), u64)); c(u16(1), u16(length(b)), as.raw(b)) }
F <- 2^32 - 1
dz <- zukomp::komp_compress(A, codec = "deflate-raw")
cases <- list(
  "usize in zip64 extra" = list(list(name = "a.npy", data = A, cusize = F, cextra = ex(length(A)))),
  "csize in zip64 extra" = list(list(name = "a.npy", data = A, ccsize = F, cextra = ex(length(A)))),
  "both in extra" = list(list(name = "a.npy", data = A, cusize = F, ccsize = F, cextra = ex(length(A), length(A)))),
  "all three in extra" = list(list(name = "a.npy", data = A, cusize = F, ccsize = F, coffset = F, cextra = ex(length(A), length(A), 0))),
  "offset only in extra (2nd member)" = list(list(name = "a.npy", data = A), list(name = "b.npy", data = B, coffset = F, cextra = ex(30 + 5 + length(A)))),
  "deflate usize in extra" = list(list(name = "a.npy", data = A, method = 8, cusize = F, cextra = ex(length(A)))),
  "deflate csize in extra" = list(list(name = "a.npy", data = A, method = 8, ccsize = F, cextra = ex(length(dz)))),
  "extra too short for usize" = list(list(name = "a.npy", data = A, cusize = F, cextra = c(u16(1), u16(4), u32(length(A))))),
  "FFFFFFFF usize, no extra" = list(list(name = "a.npy", data = A, cusize = F)),
  "zip64 extra after another extra" = list(list(name = "a.npy", data = A, cusize = F, cextra = c(u16(0x5455), u16(5), as.raw(1:5), ex(length(A))))),
  "two zip64 extras" = list(list(name = "a.npy", data = A, cusize = F, cextra = c(ex(length(A)), ex(7)))),
  "unneeded zip64 extra with junk" = list(list(name = "a.npy", data = A, cextra = ex(999, 999, 999))),
  "extra usize 2^53+1 w/ stored" = list(list(name = "a.npy", data = A, cusize = F, ccsize = F, cextra = ex(2^53, 2^53)))
)
for (nm in names(cases)) { r <- try1(npy_decode(zip_build(cases[[nm]]))); cat(sprintf("%-36s %s\n", nm, if (r$ok) paste0("OK ", paste(names(r$v), vapply(r$v, function(v) paste(v, collapse = ","), ""), sep = "=", collapse = " ; ")) else paste(r$cls, r$msg))) }
# ZIP64 end records by hand
z <- zip_build(list(list(name = "a.npy", data = A), list(name = "b.npy", data = B)))
n <- length(z); eocd <- z[(n - 21):n]; body <- z[1:(n - 22)]
cdoff <- sum(as.integer(eocd[17:20]) * 256^(0:3)); cdsize <- sum(as.integer(eocd[13:16]) * 256^(0:3))
z64 <- function(count = 2, size = cdsize, off = cdoff, mark = c("n", "size", "off"), locoff = length(body), sig = c(0x50, 0x4b, 6, 6), n16 = NULL) {
  rec <- c(as.raw(sig), u64(44), u16(45), u16(45), u32(0), u32(0), u64(count), u64(count), u64(size), u64(off))
  loc <- c(as.raw(c(0x50, 0x4b, 6, 7)), u32(0), u64(locoff), u32(1))
  e <- c(as.raw(c(0x50, 0x4b, 5, 6)), u16(0), u16(0), u16(if ("n" %in% mark) 0xFFFF else if (is.null(n16)) 2 else n16), u16(if ("n" %in% mark) 0xFFFF else if (is.null(n16)) 2 else n16),
         u32(if ("size" %in% mark) F else cdsize), u32(if ("off" %in% mark) F else cdoff), u16(0))
  c(body, rec, loc, e)
}
t2 <- function(label, x, ...) { r <- try1(npy_decode(x, ...)); cat(sprintf("%-36s %s\n", label, if (r$ok) paste0("OK [", paste(names(r$v), collapse = ","), "]") else paste(r$cls, r$msg))) }
t2("zip64 eocd all marked", z64()); t2("zip64 only count marked", z64(mark = "n")); t2("zip64 only off marked", z64(mark = "off")); t2("zip64 only size marked", z64(mark = "size"))
t2("zip64 present, nothing marked", z64(mark = character())); t2("zip64 present, unmarked, z64 count=1", z64(mark = character(), count = 1))
t2("zip64 count 1 (of 2)", z64(count = 1)); t2("zip64 count 3", z64(count = 3)); t2("zip64 count 2^40", z64(count = 2^40)); t2("zip64 count 2^40 max_members 2^53", z64(count = 2^40), max_members = 2^53)
t2("zip64 locator -> past end", z64(locoff = length(body) + 1000)); t2("zip64 locator -> 0 (wrong sig)", z64(locoff = 0)); t2("zip64 record sig bad", z64(sig = c(0x50, 0x4b, 6, 5)))
t2("zip64 size 2^60", z64(size = 2^60)); t2("zip64 off 2^60", z64(off = 2^60)); t2("marked but no zip64 records", { e <- eocd; e[9:12] <- as.raw(0xff); c(body, e) })
