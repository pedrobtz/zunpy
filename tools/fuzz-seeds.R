# Writes the fuzz seed corpus to fuzz/seeds/ (or the directory given): one
# valid header of each shape the grammar knows, each preceded by the
# harness's options byte (0: the default limits). Run from the package root
# and commit the result; r-actions' fuzz.yml reads fuzz/seeds.
source("tools/npy-bytes.R")
out <- commandArgs(TRUE)[1]
if (is.na(out)) out <- "fuzz/seeds"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

seeds <- list(
  f8 = npy_header_bytes(npy_dict("'<f8'", "(3, 4)"), raw(96)),
  scalar = npy_header_bytes(npy_dict("'>f2'", "()"), raw(2)),
  fortran = npy_header_bytes(npy_dict("'<i4'", "(2, 3)", "True"), raw(24)),
  empty = npy_header_bytes(npy_dict("'|u1'", "(0, 5)")),
  strings = npy_header_bytes(npy_dict("'<U3'", "(2,)"), raw(24)),
  bytes = npy_header_bytes(npy_dict("'|S2'", "(2,)"), raw(4)),
  datetime = npy_header_bytes(npy_dict("'<M8[ns]'", "(1,)"), raw(8)),
  record = npy_header_bytes(paste0(
    "{'descr': [(('T', 'a'), '<u4'), ('', '|V4'), ('b', '<f8', (3,)), ",
    "('c', '<U2')], 'fortran_order': False, 'shape': (1,), }"
  ), raw(40)),
  record_dict = npy_header_bytes(paste0(
    "{'descr': {'names': ['a', 'b'], 'formats': ['<i4', '<f8'], ",
    "'offsets': [0, 8], 'itemsize': 16, 'titles': [None, 'B'], ",
    "'aligned': True}, 'fortran_order': False, 'shape': (1,), }"
  ), raw(16)),
  escapes = npy_header_bytes(paste0(
    "{\"descr\": [('a\\'\\x41\\u00e9\\U0001F600', '<i4')], ",
    "\"fortran_order\": False, \"shape\": (1,)}"
  ), raw(4)),
  v2 = npy_header_bytes(npy_dict("'<c16'"), raw(16), version = 2L),
  v3 = npy_header_bytes(
    "{'descr': [('é', '<i2')], 'fortran_order': False, 'shape': (1,), }",
    raw(2), version = 3L
  )
)
for (name in names(seeds)) {
  writeBin(c(as.raw(0), seeds[[name]]), file.path(out, paste0(name, ".bin")))
}
cat(length(seeds), "seeds written to", out, "\n")
