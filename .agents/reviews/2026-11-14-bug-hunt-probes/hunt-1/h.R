.libPaths(c("HUNT_ROOT/lib", .libPaths()))
suppressMessages(library(zunpy))
T <- function(label, expr) {
  r <- tryCatch(withCallingHandlers(expr, warning = function(w) {cat("  [warn]", conditionMessage(w), "\n"); invokeRestart("muffleWarning")}),
                error = function(e) structure(list(m = conditionMessage(e), c = class(e)[1]), class = "ERR"))
  cat("==", label, "\n")
  if (inherits(r, "ERR")) cat("  ERROR<", r$c, ">", r$m, "\n") else { str(r, vec.len = 8) }
  invisible(r)
}
mk <- function(dict, data = raw(), ver = 1) {
  d <- charToRaw(dict); pre <- if (ver == 1) 10 else 12
  pad <- (64 - (pre + length(d) + 1) %% 64) %% 64
  h <- c(d, rep(charToRaw(" "), pad), charToRaw("\n"))
  len <- if (ver == 1) as.raw(c(length(h) %% 256, length(h) %/% 256)) else writeBin(length(h), raw(), size = 4, endian = "little")
  c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, ver, 0)), len, h, data)
}
rt <- function(x, ...) npy_decode(npy_encode(x, ...))
