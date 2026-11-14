.libPaths(c("HUNT_ROOT/lib", .libPaths()))
library(zunpy)
t <- function(label, expr) { r <- tryCatch(expr, error = function(e) paste("ERR", class(e)[1], conditionMessage(e))); cat(label, ":", if (is.raw(r)) paste("WRITTEN", rawToChar(r[11:(which(r == as.raw(10))[1] - 1)][1:70])) else r, "\n"); invisible(r) }
d <- data.frame(a = 1:6)
for (s in list(c(2, 3), c(3, 2), 6, c(6), c(2, 2), c(2, NA), c(-2, -3), c(1.5, 4), c(Inf, 0), numeric(0), c(2L, 3L), "6", c(2, 3, 1), c(1, 1, 6), rep(1, 64)[-1] |> c(6), c(rep(1, 64), 6), TRUE, list(6), 2^53)) { attr(d, "npy_shape") <- s; t(paste("shape", paste(format(s), collapse = ",")), npy_encode(d)) }
d0 <- data.frame(a = integer(0)); for (s in list(0, c(0, 0), c(3, 0, 2), c(0, 2^53), c(0, 2^53 + 2), c(0, 1e300))) { attr(d0, "npy_shape") <- s; t(paste("shape0", paste(format(s), collapse = ",")), npy_encode(d0)) }
# forged data frame
f <- structure(list(a = 1:3, b = 1:2), class = "data.frame", row.names = 1:3); t("forged cols", npy_encode(f))
f <- structure(list(a = 1:3), class = "data.frame", row.names = 1:5); t("forged rownames", npy_encode(f))
f <- structure(list(a = 1:3), class = "data.frame"); t("no row.names", npy_encode(f))
# failing second member to path / connection
p <- tempfile(fileext = ".npz"); r <- tryCatch(npy_write(list(a = 1:3, b = c(1L, NA)), p), error = function(e) conditionMessage(e)); print(r); print(file.exists(p))
con <- rawConnection(raw(0), "wb"); r <- tryCatch(npy_write(list(a = 1:3, b = c(1L, NA)), con), error = function(e) conditionMessage(e)); print(length(rawConnectionValue(con))); npy_write(list(a = 1:3), con); print(identical(rawConnectionValue(con), npy_encode(list(a = 1:3)))); close(con)
# compress arg numbers
for (cv in list(NA, 1, "TRUE", c(TRUE, TRUE), NULL)) t(paste("compress", format(cv)), npy_encode(list(a = 1), compress = cv))
# zero-length everything
for (v in list(logical(0), integer(0), character(0), complex(0), raw(0), as.Date(character(0)), as.POSIXct(character(0)), as.difftime(numeric(0), units = "secs"), factor(character(0)), matrix(integer(0), 0, 0), array(0, c(2, 0, 3)))) t(paste("empty", class(v)[1]), npy_encode(v))
t("empty C", npy_encode(array(0, c(2, 0, 3)), order = "C"))
t("empty chr S", npy_encode(character(0), dtype = "|S"))
