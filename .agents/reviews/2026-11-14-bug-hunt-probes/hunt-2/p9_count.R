# EOCD entry count smaller than the directory holds: members silently dropped?
source("lib.R"); source("ziplib.R")
A <- npy_encode(1:3); B <- npy_encode(c(1.5, 2.5)); C <- npy_encode(c(TRUE, FALSE))
base <- list(list(name = "a.npy", data = A), list(name = "b.npy", data = B), list(name = "c.npy", data = C))
writeBin(zip_build(base), "p9/ok.npz")
writeBin(zip_build(base, eocd = list(n = 2, total = 2)), "p9/count2.npz")
writeBin(zip_build(base, eocd = list(n = 0, total = 0)), "p9/count0.npz")
for (f in c("p9/ok.npz", "p9/count2.npz", "p9/count0.npz")) { cat(f, ": names =", npy_names(f), "| read =", names(npy_read(f)), "\n") }
