# Writes one hostile input per GUARD in src/znp_header.c to the directory
# given, and prints the case table tools/run-mutation-check reads:
#   guard|file|max_size max_header max_dims max_fields|status with the guard
source("tools/npy-bytes.R")
out <- commandArgs(TRUE)[1]
dir.create(out, showWarnings = FALSE, recursive = TRUE)
big <- "1099511627776"
dflt <- "4096 10000 32 1024"

cases <- list(
  list("input-size", npy_header_bytes(npy_dict("'<f8'"), raw(8)),
       "100 10000 32 1024", "ZNP_ERR_SIZE_LIMIT"),
  list("header-limit", npy_header_bytes(npy_dict("'<f8'"), raw(8)),
       "4096 60 32 1024", "ZNP_ERR_HEADER_LIMIT"),
  list("header-truncated", npy_header_bytes(npy_dict("'<f8'"), len = 192),
       dflt, "ZNP_ERR_TRUNCATED"),
  list("depth", npy_header_bytes(sprintf(
    "{'descr': '<f8', 'fortran_order': False, 'shape': (), 'x': %s}",
    paste0(strrep("[", 9), strrep("]", 9))), raw(8)), dflt, "ZNP_ERR_DEPTH"),
  list("dims", npy_header_bytes(npy_dict("'|u1'", "(1, 1, 1)"), raw(1)),
       "4096 10000 2 1024", "ZNP_ERR_DIMS_LIMIT"),
  list("negative-dim", npy_header_bytes(npy_dict("'|u1'", "(-1,)")),
       dflt, "ZNP_ERR_SHAPE"),
  list("fields", npy_header_bytes(
    "{'descr': [('a', '|u1'), ('b', '|u1')], 'fortran_order': False, 'shape': (1,), }",
    raw(2)), "4096 10000 32 1", "ZNP_ERR_FIELDS_LIMIT"),
  list("duplicate-field", npy_header_bytes(
    "{'descr': [('a', '|u1'), ('a', '|u1')], 'fortran_order': False, 'shape': (1,), }",
    raw(2)), dflt, "ZNP_ERR_LAYOUT"),
  list("field-past-itemsize", npy_header_bytes(paste0(
    "{'descr': {'names': ['a'], 'formats': ['<i4'], 'offsets': [4], ",
    "'itemsize': 6}, 'fortran_order': False, 'shape': (1,), }"), raw(6)),
    dflt, "ZNP_ERR_LAYOUT"),
  list("overlap", npy_header_bytes(paste0(
    "{'descr': {'names': ['a', 'b'], 'formats': ['<i4', '<i4'], ",
    "'offsets': [0, 2]}, 'fortran_order': False, 'shape': (1,), }"), raw(6)),
    dflt, "ZNP_ERR_LAYOUT"),
  list("key-type", npy_header_bytes(
    "{'descr': '<f8', 'fortran_order': False, 'shape': (), 1: 2}", raw(8)),
    dflt, "ZNP_ERR_TYPE"),
  list("duplicate-key", npy_header_bytes(
    "{'descr': '<f8', 'descr': '<f8', 'fortran_order': False, 'shape': (), }",
    raw(8)), dflt, "ZNP_ERR_KEY"),
  list("itemsize", npy_header_bytes(npy_dict("'<U1000000'", "(0,)")),
       dflt, "ZNP_ERR_SIZE_LIMIT"),
  list("columns", npy_header_bytes(
    "{'descr': [('a', '|u1', (3,))], 'fortran_order': False, 'shape': (1,), }",
    raw(3)), "4096 10000 32 2", "ZNP_ERR_FIELDS_LIMIT"),
  list("zero-width", npy_header_bytes(npy_dict("'|S0'", sprintf("(%s,)", big))),
       dflt, "ZNP_ERR_SIZE_LIMIT"),
  list("declared-size", npy_header_bytes(
    npy_dict("'<f8'", sprintf("(%s, %s)", big, big))), dflt,
    "ZNP_ERR_SIZE_LIMIT"),
  list("data-truncated", npy_header_bytes(npy_dict("'<f8'", "(2,)"), raw(15)),
       dflt, "ZNP_ERR_TRUNCATED"),
  list("trailing", npy_header_bytes(npy_dict("'<f8'", "(2,)"), raw(17)),
       dflt, "ZNP_ERR_TRAILING")
)
for (k in cases) {
  f <- file.path(out, paste0(k[[1]], ".npy"))
  writeBin(k[[2]], f)
  cat(paste(k[[1]], f, k[[3]], k[[4]], sep = "|"), "\n", sep = "")
}
