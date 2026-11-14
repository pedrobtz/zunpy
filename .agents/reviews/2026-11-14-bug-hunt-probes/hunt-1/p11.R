source("h.R")
if (nzchar(Sys.getenv("HOSTILE"))) options(OutDec = ",", scipen = -5, digits = 3, warn = 2, encoding = "latin1", useFancyQuotes = TRUE)
u <- function(s) { Encoding(s) <- "UTF-8"; s }
vals <- list(
  int = 1:3, dbl = c(1.23456789012345, 2^31 + 1, 2^53 + 2, 1e-300, 123456.7), big = 1e15, lgl = c(TRUE, FALSE), cplx = c(1.5+2i),
  chr = c("a", "bbb", u("caf\xc3\xa9")), fac = factor(c("b", "a")), date = as.Date("2024-03-10") + 0:1,
  ct = as.POSIXct("2024-03-10 01:30:00", tz = "America/New_York") + c(0, 3600, 7200.25),
  dft = as.difftime(c(1, 2), units = "hours"),
  dfs = as.difftime(c(0.001, 1234567.891), units = "secs"),
  i64 = bit64::as.integer64(c("9007199254740993", "-1")), mat = matrix(c(1.5, 2, 3, 4), 2),
  df = data.frame(a = c(1.5, 100000), f = c("x", "yy"), n = c(1e5, 1e-5), stringsAsFactors = TRUE),
  shp = structure(data.frame(a = 1:100000 + 0), npy_shape = c(100000)),
  shp2 = structure(data.frame(a = 1:200000 + 0), npy_shape = c(2, 100000)),
  long = numeric(100000), wide = strrep("x", 100000)
)
for (n in names(vals)) {
  b <- tryCatch(npy_encode(vals[[n]]), error = function(e) charToRaw(paste("ERR", conditionMessage(e))))
  h <- tryCatch(npy_header(b), error = function(e) NULL)
  cat(n, length(b), paste(as.integer(b[1:10]), collapse = " "), sum(as.integer(b)), if (is.character(h$descr)) h$descr else "struct", paste(sprintf("%.0f", h$shape), collapse = "x"), "\n")
  writeBin(b, sprintf("out/h_%s_%s.npy", if (nzchar(Sys.getenv("HOSTILE"))) "H" else "N", n))
}
ct <- npy_decode(npy_encode(vals$ct)); cat(sprintf("%.6f", unclass(ct)), attr(ct, "tzone"), "\n")
# errors with big indexes
e <- tryCatch(npy_encode(c(numeric(123456), 1.5), dtype = "<i4"), error = function(e) e); cat(conditionMessage(e), " index=", sprintf("%.0f", e$index), "\n")
e <- tryCatch(npy_encode(c(rep("a", 100000), NA)), error = function(e) e); cat(conditionMessage(e), "\n")
e <- tryCatch(npy_encode(data.frame(a = c(numeric(100000), 1.5)), dtype = c(a = "<i4")), error = function(e) e); cat(conditionMessage(e), "\n")
e <- tryCatch(npy_decode(npy_encode(1:3), max_size = 100000 - 99990), error = function(e) e); cat(conditionMessage(e), "\n")
e <- tryCatch(npy_read("out/m.npy", max_size = 100), error = function(e) e); cat(conditionMessage(e), "\n")
e <- tryCatch(npy_decode(npy_encode(1:3), max_size = 1e5 + 0.5), error = function(e) e); cat(conditionMessage(e), "\n")
z <- npy_encode(list(k = vals$dbl, s = vals$chr)); cat(length(z), sum(as.integer(z)), "\n")
print(npy_names(z)); str(npy_decode(z))
str(npy_decode(npy_encode(vals$df)))
print(zunpy_info()$version)
