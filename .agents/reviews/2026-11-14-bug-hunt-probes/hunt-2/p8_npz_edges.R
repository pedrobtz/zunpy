source("lib.R"); source("ziplib.R")
A <- npy_encode(1:3); B <- npy_encode(c(1.5, 2.5)); C <- npy_encode(c(TRUE, FALSE))
base <- list(list(name = "a.npy", data = A), list(name = "b.npy", data = B, method = 8), list(name = "c.npy", data = C))
z <- zip_build(base)
show("base", npy_decode(z)); str(npy_decode(z))
cat("== names selection\n")
for (nm in list("b", c("c", "a"), c("a", "a"), c("b", "a", "b"), character(), "zz", NA_character_, c("a", NA), 1, list("a"), "a.npy", "A", factor("a"), c(x = "a"))) {
  r <- try1(npy_decode(z, names = nm)); cat(sprintf("names=%-22s -> %s\n", deparse(nm), if (r$ok) paste0("[", paste(names(r$v), collapse = ","), "] len ", length(r$v)) else paste(r$cls, substr(r$msg, 1, 70))))
}
f <- tempfile(fileext = ".npz"); writeBin(z, f)
r <- try1(npy_read(f, names = c("c", "a"))); cat("read names c,a:", names(r$v), "\n")
r <- try1(npy_read(f, "c")); cat("read positional names:", if (r$ok) names(r$v) else paste(r$cls, r$msg), "\n")
r <- try1(npy_read(f, na = "allow")); cat("read na=allow:", if (r$ok) names(r$v) else paste(r$cls, r$msg), "\n")
r <- try1(npy_read(f, n = "a")); cat("read n='a' (partial):", if (r$ok) names(r$v) else paste(r$cls, r$msg), "\n")
r <- try1(npy_read(f, name = "a")); cat("read name='a' (partial):", if (r$ok) names(r$v) else paste(r$cls, r$msg), "\n")
r <- try1(npy_decode(A, names = "a")); cat("names on .npy:", r$cls, r$msg, "\n")
r <- try1(npy_decode(A, names = character())); cat("names=character() on .npy:", if (r$ok) "OK" else paste(r$cls, r$msg), "\n")
cat("== repeatability\n"); cat(identical(npy_decode(z), npy_decode(z)), identical(npy_read(f), npy_decode(z)), "\n")
cat("== broken third member: what comes back\n")
bad <- base; bad[[3]]$crc <- 12345
zb <- zip_build(bad)
got <- "nothing"; r <- try1(got <- npy_decode(zb)); cat(r$cls, r$msg, "| member:", r$e$member, "offset:", r$e$offset, "| got:", deparse(got), "| warnings before:", r$w, "\n")
show("  names=c(a,b) of broken", names(npy_decode(zb, names = c("a", "b"))))
show("  npy_names of broken", npy_names(zb))
# warning in member 1 then error in member 3
W <- mk(H("'i4'", "(1,)"), le(5L, 4), align = 16)
bad2 <- list(list(name = "w.npy", data = W), list(name = "b.npy", data = B), list(name = "c.npy", data = C, crc = 1))
r <- try1(npy_decode(zip_build(bad2))); cat("warn-then-error:", r$cls, "| warnings:", r$w, "\n")
r <- try1(npy_decode(zip_build(bad2[1:2]))); cat("warnings ok case:", r$w, "\n")
cat("== member failures carry member + offset\n")
T3 <- A[seq_len(length(A) - 1)]
for (cs in list(list("truncated npy", list(name = "t.npy", data = T3)), list("usize lies +1 stored", list(name = "t.npy", data = A, usize = length(A) + 1)),
                list("usize lies deflate -1", list(name = "t.npy", data = A, method = 8, usize = length(A) - 1)), list("usize lies deflate +1", list(name = "t.npy", data = A, method = 8, usize = length(A) + 1)),
                list("garbage deflate", list(name = "t.npy", data = A, method = 8, payload = as.raw(rep(0xff, 40)))),
                list("deflate + trailing junk in csize", list(name = "t.npy", data = A, method = 8, payload = c(zukomp::komp_compress(A, codec = "deflate-raw"), as.raw(1:5)))),
                list("deflate truncated", list(name = "t.npy", data = A, method = 8, payload = head(zukomp::komp_compress(A, codec = "deflate-raw"), -3))),
                list("usize 0 deflate empty", list(name = "t.npy", data = raw(), method = 8)), list("usize 0 stored", list(name = "t.npy", data = raw())),
                list("crc 0", list(name = "t.npy", data = A, crc = 0)), list("method 9", list(name = "t.npy", data = A, method = 9)), list("method 12", list(name = "t.npy", data = A, method = 12)),
                list("encrypted flag", list(name = "t.npy", data = A, flags = 1)), list("flag 0x800 bad utf8", list(name = as.raw(c(0xe9, 0x2e, 0x6e, 0x70, 0x79)), data = A, flags = 0x800)),
                list("latin1 name no flag", list(name = as.raw(c(0xe9, 0x2e, 0x6e, 0x70, 0x79)), data = A)), list("NUL in name", list(name = as.raw(c(0x61, 0, 0x2e, 0x6e, 0x70, 0x79)), data = A)),
                list("empty name", list(name = "", data = A)), list("local name differs", list(name = "t.npy", lname = "u.npy", data = A)), list("local name longer", list(name = "t.npy", lname = "longer.npy", data = A)),
                list("local sizes zero (descriptor style)", list(name = "t.npy", data = A, lcsize = 0, lusize = 0, lcrc = 0, flags = 8)), list("local sig bad", list(name = "t.npy", data = A, lsig = c(0x50, 0x4b, 3, 5))),
                list("local extra", list(name = "t.npy", data = A, lextra = as.raw(c(0x55, 0x54, 5, 0, 1, 2, 3, 4, 5)))), list("central extra unknown", list(name = "t.npy", data = A, cextra = as.raw(c(0x55, 0x54, 5, 0, 1, 2, 3, 4, 5)))),
                list("central extra truncated hdr", list(name = "t.npy", data = A, cextra = as.raw(c(0x55, 0x54, 5)))), list("central extra size overrun", list(name = "t.npy", data = A, cextra = as.raw(c(0x55, 0x54, 9, 0, 1, 2)))),
                list("entry comment", list(name = "t.npy", data = A, klen = 1, kcomment = charToRaw("hi"))), list("disk 1", list(name = "t.npy", data = A, disk = 1)),
                list("nested npz member", list(name = "t.npy", data = z)), list("member is .npz named x.npz", list(name = "x.npz", data = z)))) {
  r <- try1(npy_decode(zip_build(list(cs[[2]]))))
  cat(sprintf("%-36s %s\n", cs[[1]], if (r$ok) paste0("OK names=[", paste(encodeString(names(r$v)), collapse = ","), "] enc=", paste(Encoding(names(r$v)), collapse = ","), " v=", paste(format(r$v[[1]]), collapse = ",")) else
      paste0(r$cls, ": ", r$msg, " {member=", format(r$e$member), ", offset=", format(r$e$offset), "}")))
}
cat("== max_members straddle\n")
for (d in c(2, 3, 4, 0)) show(paste("max_members", d), length(npy_decode(z, max_members = d)))
for (d in c(2, 3)) show(paste("npy_names max_members", d), npy_names(z, max_members = d))
show("max_members 2, names='a'", names(npy_decode(z, names = "a", max_members = 2)))
for (m in list(NA, -1, 1.5, Inf, 2^53, 2^53 + 2)) show(paste("max_members", deparse(m)), length(npy_decode(z, max_members = m)))
cat("== max_size vs archive / declared total\n")
tot <- length(A) + length(B) + length(C); cat("archive", length(z), "declared total", tot, "\n")
for (d in c(length(z) - 1, length(z))) show(paste("max_size", d), length(npy_decode(z, max_size = d)))
# deflated archive where declared total > archive size
big <- npy_encode(numeric(5000)); zd <- zip_build(list(list(name = "z.npy", data = big, method = 8), list(name = "y.npy", data = big, method = 8)))
cat("deflated archive", length(zd), "declared total", 2 * length(big), "\n")
for (d in c(2 * length(big) - 1, 2 * length(big), 2 * length(big) + 1)) show(paste("max_size", d), length(npy_decode(zd, max_size = d)))
show("max_size total-1, names='z'", length(npy_decode(zd, max_size = 2 * length(big) - 1, names = "z")))
show("npy_names max_size total-1", npy_names(zd, max_size = 2 * length(big) - 1))
writeBin(zd, f); show("read path max_size total-1", length(npy_read(f, max_size = 2 * length(big) - 1)))
show("npy_names path max_size total-1", npy_names(f, max_size = 2 * length(big) - 1))
show("npy_names path max_size archive-1", npy_names(f, max_size = length(zd) - 1))
cat("== EOCD numbers\n")
for (cs in list(list("n < total", list(n = 2)), list("total < actual", list(n = 2, total = 2)), list("total > actual", list(n = 4, total = 4)), list("disk 1", list(disk = 1)), list("cdisk 1", list(cdisk = 1)),
                list("csize short", list(csize = 10)), list("csize 0", list(csize = 0)), list("coffset +1", list(coffset = NULL)), list("coffset huge", list(coffset = 2^32 - 2)),
                list("n=0 total=0", list(n = 0, total = 0)), list("csize larger than CD (pre junk)", list(pre = as.raw(rep(0, 8)), csize = NULL)))) {
  e <- cs[[2]]
  if (cs[[1]] == "coffset +1") e <- list(coffset = length(z) - 22 - 3 * 0 - (length(z) - 22 - which(z[1:(length(z) - 3)] == as.raw(0x50) & z[2:(length(z) - 2)] == as.raw(0x4b) & z[3:(length(z) - 1)] == as.raw(1))[1] + 1) + 1)
  if (cs[[1]] == "csize larger than CD (pre junk)") e <- list(pre = as.raw(rep(0, 8)), csize = (length(z) - 22) - (which(z[1:(length(z) - 3)] == as.raw(0x50) & z[2:(length(z) - 2)] == as.raw(0x4b) & z[3:(length(z) - 1)] == as.raw(1))[1] - 1) + 8)
  r <- try1(npy_decode(zip_build(base, eocd = e)))
  cat(sprintf("%-34s %s\n", cs[[1]], if (r$ok) paste0("OK [", paste(names(r$v), collapse = ","), "]") else paste0(r$cls, ": ", r$msg)))
}
show("tail junk after EOCD", names(npy_decode(zip_build(base, tail = as.raw(0)))))
show("comment", names(npy_decode(zip_build(base, comment = charToRaw("hello")))))
show("21 bytes", npy_decode(as.raw(c(0x50, 0x4b, 5, 6, rep(0, 17)))))
show("22 bytes empty", npy_decode(as.raw(c(0x50, 0x4b, 5, 6, rep(0, 18)))))
show("PK only", npy_decode(as.raw(c(0x50, 0x4b))))
show("npy_names on .npy", npy_names(A))
show("npy_header on .npz", npy_header(z))
