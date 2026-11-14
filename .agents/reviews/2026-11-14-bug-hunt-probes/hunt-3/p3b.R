.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
print(Sys.getlocale()); print(l10n_info())
x <- c("a", "hé", "ÿ"); print(Encoding(x))
l1 <- "\xe9t\xe9"; Encoding(l1) <- "latin1"
tail128 <- function(r) r[-(1:128)]
for (v in list(x, l1)) for (e in c("UTF-8","latin1","bytes")) { cat(e, ": "); print(tryCatch(tail128(npy_encode(v, dtype="|S", encoding=e)), error=function(e) conditionMessage(e))) }
print(tail128(npy_encode(x)))
d <- data.frame(1); names(d) <- "hé"; r <- npy_encode(d); print(r[1:40]); 
names(d) <- l1; r <- npy_encode(d); print(r[1:40])
names(d) <- "€"; r <- npy_encode(d); print(r[1:40])
r <- npy_encode(setNames(list(1), "hé")); print(rawToChar(r[31:40])); print(r[1:12])
r <- npy_encode(setNames(list(1), l1)); print(r[31:40]); print(r[1:12])
