.libPaths(c("HUNT_ROOT/lib", .libPaths()))
suppressMessages(library(zunpy))
dir <- commandArgs(TRUE)[1]
t <- read.delim(file.path(dir, "numpy.tsv"), header = FALSE, quote = "", colClasses = "character")
for (i in seq_len(nrow(t))) {
  f <- file.path(dir, paste0(t$V1[i], ".npy"))
  x <- readBin(f, "raw", file.size(f))
  w <- character()
  r <- tryCatch(withCallingHandlers({
    v <- npy_decode(x)
    paste("OK", paste(class(v), collapse = "/"), "dim", paste(dim(v), collapse = ","), ":",
          paste(if (is.list(v)) vapply(v, function(e) paste(as.character(e), collapse = ""), "") else format(unclass(v)), collapse = " "))
  }, warning = function(c) { w <<- c(w, class(c)[1]); invokeRestart("muffleWarning") }),
  error = function(e) paste("ERR", class(e)[1], conditionMessage(e)))
  cat(sprintf("%s %-18s\n   np: %s\n   zu: %s %s\n", t$V1[i], t$V2[i], t$V3[i], r, paste(w, collapse = ",")))
}
