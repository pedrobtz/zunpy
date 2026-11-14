.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
# the largest datetime64[ns] NumPy can hold, as a file
hdr <- npy_encode(structure(0, class = c("POSIXct", "POSIXt")), unit = "ns")
f <- hdr; f[129:136] <- as.raw(c(0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f))
x <- npy_decode(f); print(format(as.numeric(x), digits = 20))
print(tryCatch(npy_encode(x, unit = "ns"), error = function(e) conditionMessage(e)))
for (v in c(9223372036.9, 9223372036.85, -9223372036.9)) print(tryCatch(length(npy_encode(structure(v, class = c("POSIXct", "POSIXt")), unit = "ns")), error = function(e) conditionMessage(e)))
