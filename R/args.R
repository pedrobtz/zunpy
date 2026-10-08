# Argument checks shared by the exported functions. Each raises
# zunpy_invalid_argument naming the argument.

znp_check_raw <- function(x, arg = "x", call = NULL) {
  if (!is.raw(x)) {
    znp_invalid_argument(arg, sprintf("`%s` must be a raw vector.", arg),
                         call = call)
  }
  invisible(x)
}

# A whole number in [lo, hi], given as a double or an integer.
znp_check_count <- function(x, arg, lo, hi, call = NULL) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x != trunc(x) ||
      x < lo || x > hi) {
    znp_invalid_argument(arg, sprintf(
      "`%s` must be a whole number between %s and %s.",
      arg, format(lo, scientific = FALSE), format(hi, scientific = FALSE)
    ), call = call)
  }
  as.double(x)
}

# The limits of design section 12, checked and packed for C.
znp_limits <- function(max_size, max_header, max_dims, max_fields,
                       call = NULL) {
  c(
    znp_check_count(max_size, "max_size", 0, 2^53, call),
    znp_check_count(max_header, "max_header", 0, 2^32 - 1, call),
    znp_check_count(max_dims, "max_dims", 0, 64, call),
    znp_check_count(max_fields, "max_fields", 1, .Machine$integer.max, call)
  )
}
