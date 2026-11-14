source("lib.R")
for (s in c("(4294967296, 4294967296)", "(1125899906842624,)", "(1125899906842625,)", "(4294967296, 4294967296, 4294967296)")) for (d in c("'<f8'", "'|u1'", "'|S0'", "'<U1'")) {
  r <- try1(npy_header(mk(H(d, s)))); cat(sprintf("%-6s %-40s %s\n", d, s, if (r$ok) paste("OK shape", paste(format(r$v$shape, digits = 17), collapse = " x ")) else paste(r$cls, r$msg, "| limit:", r$e$limit)))
}
for (s in c("(9007199254740992,)", "(9007199254740993,)", "(9223372036854775807,)", "(0, 9223372036854775807)", "(0, 9007199254740993)", "(9223372036854775808,)", "(0, 18446744073709551616)")) for (d in c("'|u1'", "'|S0'")) {
  r <- try1(npy_header(mk(H(d, s)))); cat(sprintf("%-6s %-40s %s\n", d, s, if (r$ok) paste("OK shape", paste(format(r$v$shape, digits = 17), collapse = " x ")) else paste(r$cls, r$msg)))
}
