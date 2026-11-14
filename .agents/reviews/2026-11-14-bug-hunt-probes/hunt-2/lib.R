.libPaths(c("HUNT_ROOT/lib", .libPaths()))
suppressMessages(library(zunpy))
# a .npy with an arbitrary header text
mk <- function(hdr, data = raw(), ver = 1L, align = 64L, raw_hdr = NULL, pad = NULL) {
  h <- if (is.null(raw_hdr)) charToRaw(hdr) else raw_hdr
  pre <- if (ver == 1L) 10L else 12L
  if (is.null(pad)) pad <- (-(pre + length(h) + 1L)) %% align
  h <- c(h, rep(as.raw(0x20), pad), as.raw(0x0a))
  n <- length(h)
  len <- if (ver == 1L) as.raw(c(n %% 256, n %/% 256)) else as.raw(c(n %% 256, (n %/% 256) %% 256, (n %/% 65536) %% 256, n %/% 16777216))
  c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, ver, 0)), len, h, data)
}
H <- function(descr, shape, fo = FALSE) sprintf("{'descr': %s, 'fortran_order': %s, 'shape': %s, }", descr, if (fo) "True" else "False", shape)
le <- function(x, size) writeBin(x, raw(), size = size, endian = "little")
i64 <- function(s) { # decimal string -> 8 LE bytes, via two's complement on big ints (uses gmp-free arithmetic)
  stopifnot(requireNamespace("bit64", quietly = TRUE))
  v <- bit64::as.integer64(s); writeBin(unclass(v), raw(), size = 8, endian = "little")
}
try1 <- function(expr, show = TRUE) {
  w <- character()
  r <- tryCatch(withCallingHandlers(list(ok = TRUE, v = expr),
    warning = function(c) { w <<- c(w, class(c)[1]); invokeRestart("muffleWarning") }),
    error = function(e) list(ok = FALSE, cls = class(e)[1], msg = conditionMessage(e), e = e))
  r$w <- w
  r
}
show <- function(label, expr) {
  r <- try1(expr)
  if (r$ok) {
    cat(sprintf("%-34s OK ", label)); 
    v <- r$v
    cat(paste(class(v), collapse = "/"), if (!is.null(dim(v))) paste0("dim=", paste(dim(v), collapse = "x")), "len", length(v), ":",
        paste(utils::head(if (is.list(v) && !is.data.frame(v)) vapply(v, function(e) paste(format(e), collapse = ""), "") else if (is.data.frame(v)) paste(names(v), collapse = ";") else format(v, digits = 17), 8), collapse = " "),
        if (length(r$w)) paste0("[warn: ", paste(r$w, collapse = ","), "]"), "\n")
  } else cat(sprintf("%-34s ERR %s: %s%s\n", label, r$cls, r$msg,
        paste0(" {", paste(vapply(setdiff(names(r$e), c("message", "call")), function(n) paste0(n, "=", format(r$e[[n]], scientific = FALSE)), ""), collapse = ", "), "}")))
  invisible(r)
}
