source("lib.R")
d <- tempfile(); dir.create(d)
wr <- function(x, name) { f <- file.path(d, name); writeBin(x, f); f }
small <- npy_encode(as.raw(sample(0:255, 40, TRUE)))            # incompressible-ish, tiny
big <- npy_encode(rep(1:4, 5000))                                # compressible
for (nm in c("small", "big")) {
  x <- get(nm); f <- wr(x, paste0(nm, ".npy"))
  for (cmp in c("gzip", "bzip2", "xz")) {
    g <- file.path(d, paste0(nm, ".npy.", cmp)); con <- switch(cmp, gzip = gzfile(g, "wb"), bzip2 = bzfile(g, "wb"), xz = xzfile(g, "wb")); writeBin(x, con); close(con)
    r <- try1(npy_read(g)); cat(sprintf("%-6s %-5s path (%5d bytes on disk, %5d raw): %s\n", nm, cmp, file.size(g), length(x), if (r$ok) paste("OK identical to plain:", identical(r$v, npy_decode(x)), "len", length(r$v)) else paste(r$cls, r$msg)))
    r <- try1(npy_header(g)); cat(sprintf("       npy_header(path): %s\n", if (r$ok) paste("OK shape", r$v$shape) else paste(r$cls, r$msg)))
    con <- file(g, "rb"); r <- try1(npy_read(con)); close(con); cat(sprintf("       file(g,'rb') connection: %s\n", if (r$ok) paste("OK identical:", identical(r$v, npy_decode(x))) else paste(r$cls, r$msg)))
    con <- gzfile(g); r <- try1(npy_read(con)); try(close(con), silent = TRUE); cat(sprintf("       gzfile(g) unopened connection: %s\n", if (r$ok) paste("OK identical:", identical(r$v, npy_decode(x))) else paste(r$cls, r$msg)))
    r <- try1(npy_read(g, max_size = file.size(g))); cat(sprintf("       path, max_size = on-disk size: %s\n", if (r$ok) "OK" else paste(r$cls, r$msg)))
    r <- try1(npy_read(g, max_size = 200)); cat(sprintf("       path, max_size = 200: %s\n", if (r$ok) paste("OK len", length(r$v)) else paste(r$cls, r$msg)))
  }
}
