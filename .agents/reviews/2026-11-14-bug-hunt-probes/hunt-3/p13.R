.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
# Internal builder with a declared uncompressed size the payload does not have: only the directory encoding is under test.
us <- c(2^31 - 1, 2^31, 2^32 - 2, 2^32 - 1, 2^32, 2^33 + 5)
out <- .Call(zunpy:::zunpy_zip_build, paste0("m", seq_along(us), ".npy"), rep(8L, length(us)), rep(0, length(us)), us, rep(list(as.raw(c(3, 0))), length(us)))
writeBin(out, "out13/fake_usize.npz")
