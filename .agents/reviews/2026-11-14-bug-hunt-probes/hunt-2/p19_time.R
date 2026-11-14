source("lib.R"); suppressMessages(library(bit64))
for (u in c("ms", "us", "ns")) {
  e <- npy_read(sprintf("p19/exp_%s.npy", u)); raw <- npy_read(sprintf("p19/raw_%s.npy", u), int64 = "integer64")
  for (k in c("dt", "td")) for (be in c("", "_be")) {
    v <- npy_read(sprintf("p19/%s_%s%s.npy", k, u, be))
    d <- which(unclass(v) != e | is.na(v) != is.na(e))
    cat(k, u, be, "n", length(e), "class", class(v)[1], "mismatches vs correctly rounded:", length(d), "\n")
    if (length(d)) for (i in utils::head(d, 5)) cat("    count", as.character(raw[i]), "got", format(unclass(v)[i], digits = 17), "want", format(e[i], digits = 17), "\n")
    vi <- npy_read(sprintf("p19/%s_%s%s.npy", k, u, be), datetime = "integer64")
    if (!identical(as.character(vi), as.character(raw))) cat("   integer64 counts differ!\n")
  }
}
