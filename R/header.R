# The check phase from R (design section 4): a raw vector in, the plan out,
# or a classed condition. Stage 2's npy_header() and npy_decode() are built
# on it.
znp_header_check <- function(x, max_size = 2 * 1024^3, max_header = 10000,
                             max_dims = 32, max_fields = 1024, call = NULL) {
  znp_check_raw(x, call = call)
  limits <- znp_limits(max_size, max_header, max_dims, max_fields, call)
  res <- .Call(zunpy_header_check, x, limits)
  if (res$status != "ZNP_OK") {
    znp_raise_status(res$status, res$offset, x, limits, call = call)
  }
  res$status <- NULL
  res$offset <- NULL
  res
}

# The quoted string starting at a 0-based offset, for naming the dtype in
# zunpy_unsupported_type; NA when there is none.
znp_quoted_at <- function(x, offset) {
  i <- offset + 1
  if (i > length(x) || !(x[i] %in% as.raw(c(0x22, 0x27)))) {
    return(NA_character_)
  }
  end <- which(x[-seq_len(i)] == x[i])
  if (length(end) == 0L) {
    return(NA_character_)
  }
  s <- rawToChar(x[(i + 1):(i + end[1] - 1)])
  Encoding(s) <- "latin1"
  enc2utf8(s)
}
