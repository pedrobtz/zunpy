source("h.R")
cat(Sys.getlocale(), "\n")
u <- function(...) { s <- rawToChar(as.raw(c(...))); Encoding(s) <- "UTF-8"; s }
cafe <- u(0x63,0x61,0x66,0xc3,0xa9); jp <- u(0xe6,0x97,0xa5,0xe6,0x9c,0xac); emo <- u(0xf0,0x9f,0x98,0x80)
x <- c(cafe, jp, emo, "abc")
hex <- function(s) vapply(s, function(z) paste(charToRaw(z), collapse=""), "")
show <- function(l, r) cat(sprintf("%-28s enc=%s hex=%s\n", l, paste(Encoding(r), collapse=","), paste(hex(r), collapse=" ")))
show("marked UTF-8 <U", rt(x))
show("marked UTF-8 |S", rt(x, dtype="|S"))
show("|S dec latin1", npy_decode(npy_encode(cafe, dtype="|S", encoding="latin1"), encoding="latin1"))
cat("S latin1 file bytes:", tail(as.character(npy_encode(cafe, dtype="|S", encoding="latin1")), 4), "\n")
l1 <- rawToChar(as.raw(c(0x63,0x61,0x66,0xe9))); Encoding(l1) <- "latin1"
show("latin1-marked <U", rt(l1))
r <- T("latin1-marked |S latin1", npy_encode(l1, dtype="|S", encoding="latin1"))
if (is.raw(r)) cat(tail(as.character(r), 5), "\n")
r <- T("latin1-marked |S bytes", npy_encode(l1, dtype="|S", encoding="bytes"))
if (is.raw(r)) cat(tail(as.character(r), 5), "\n")
r <- T("latin1-marked |S utf8", npy_encode(l1, dtype="|S"))
if (is.raw(r)) cat(tail(as.character(r), 5), "\n")
r <- T("utf8-marked |S bytes", npy_encode(cafe, dtype="|S", encoding="bytes"))
if (is.raw(r)) cat(tail(as.character(r), 5), "\n")
# unmarked native
un <- rawToChar(as.raw(c(0x63,0x61,0x66,0xc3,0xa9)))
r <- T("unmarked utf8 bytes <U", npy_encode(un)); if (is.raw(r)) {print(npy_header(r)$descr); show("  back", npy_decode(r))}
r <- T("unmarked utf8 bytes |S", npy_encode(un, dtype="|S")); if (is.raw(r)) {print(npy_header(r)$descr)}
r <- T("unmarked utf8 bytes |S latin1", npy_encode(un, dtype="|S", encoding="latin1")); if (is.raw(r)) {print(npy_header(r)$descr); cat(tail(as.character(r), 5), "\n")}
r <- T("utf8 jp |S latin1", npy_encode(jp, dtype="|S", encoding="latin1"))
if (is.raw(r)) {print(npy_header(r)$descr); cat(tail(as.character(r), 8), "\n")}
# names
df <- data.frame(1, 2); names(df) <- c(cafe, "b")
r <- T("df utf8 name", npy_encode(df)); if (is.raw(r)) show("  names", names(npy_decode(r)))
names(df) <- c(un, "b")
r <- T("df unmarked name", npy_encode(df)); if (is.raw(r)) show("  names", names(npy_decode(r)))
names(df) <- c(l1, "b")
r <- T("df latin1 name", npy_encode(df)); if (is.raw(r)) show("  names", names(npy_decode(r)))
l <- setNames(list(1), cafe); r <- T("npz utf8 name", npy_encode(l)); if (is.raw(r)) {show("  names", names(npy_decode(r))); show("  npy_names", npy_names(r))}
l <- setNames(list(1), un); r <- T("npz unmarked name", npy_encode(l)); if (is.raw(r)) show("  names", names(npy_decode(r)))
l <- setNames(list(1), l1); r <- T("npz latin1 name", npy_encode(l)); if (is.raw(r)) show("  names", names(npy_decode(r)))
