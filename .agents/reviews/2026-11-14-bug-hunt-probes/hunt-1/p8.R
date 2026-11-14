source("h.R")
f <- "out/m.npy"
n0 <- nrow(showConnections(all=TRUE))
chk <- function(l) { n <- nrow(showConnections(all=TRUE)); cat(l, "connections leaked:", n - n0, "\n"); n0 <<- n }
try(npy_read(file(f), max_header=10), silent=TRUE); chk("max_header err")
try(npy_read(file(f), max_dims=1), silent=TRUE); chk("max_dims err")
try(npy_read(file(f), max_size=10), silent=TRUE); chk("max_size err")
try(npy_read(file(f), na="bogus"), silent=TRUE); chk("bad option")
try(npy_read(file(f), names="a"), silent=TRUE); chk("names on npy")
try(npy_header(file(f), max_header=-1), silent=TRUE); chk("header bad arg")
try(npy_names(file(f), max_size=-1), silent=TRUE); chk("names bad arg")
try(npy_write(c(1L,NA), file("out/zz.npy")), silent=TRUE); chk("write encode err"); 
npy_read(file(f)); chk("ok read")
npy_header(file(f)); chk("ok header")
npy_write(1, file("out/zz.npy")); chk("ok write")
