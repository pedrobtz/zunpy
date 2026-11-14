source("h.R")
l <- list(a = 1:3, b = c(1.5, 2), s = c("x", "yy"), l = c(TRUE, FALSE), m = matrix(1:6, 2), d = as.Date("2024-01-01"))
for (n in names(l)) { writeBin(npy_encode(l[n]), sprintf("out/s_%s.npz", n)); writeBin(npy_encode(l[n], compress=TRUE), sprintf("out/sc_%s.npz", n)) }
writeBin(npy_encode(l), "out/s_all.npz")
