# The condition hierarchy of design section 11. The class is the contract:
# callers branch on it and on the fields below, never on the message.

#' Conditions raised by zunpy
#'
#' Every error zunpy raises carries a condition class, so it can be caught
#' by kind rather than by matching the message, which may change. Every
#' class below inherits from `zunpy_error`. Offsets are 0-based byte
#' offsets into the input; in a `.npz` they count from the start of the
#' member, and `member` names it.
#'
#' \describe{
#'   \item{`zunpy_invalid_argument`}{An argument was unusable, including a
#'     `dtype` the value cannot reach. Carries `arg`.}
#'   \item{`zunpy_parse_error`}{The input is not a `.npy` or `.npz`: a bad
#'     magic string, version, header grammar or `descr`, or truncated or
#'     trailing data. Carries `offset`.}
#'   \item{`zunpy_invalid_error`}{The input is well formed but inconsistent:
#'     the shape disagrees with the data length, fields overlap, a `U`
#'     string holds a surrogate, or a checksum does not match. Carries
#'     `offset`.}
#'   \item{`zunpy_unsupported_type`}{A dtype or an R value with no
#'     counterpart: object arrays, long doubles, nested structured dtypes.
#'     Carries `dtype`.}
#'   \item{`zunpy_unrepresentable`}{A value R cannot hold: a dimension above
#'     `2^31 - 1`, or a 64-bit integer beyond `2^53` read as a double.
#'     Carries `offset` and `index`.}
#'   \item{`zunpy_na_error`}{An `NA` with no representation in the target.
#'     Carries `index`.}
#'   \item{`zunpy_range_error`}{A value does not fit the requested dtype.
#'     Carries `index`.}
#'   \item{`zunpy_limit_error`}{A limit was reached. Carries `limit`, the
#'     argument's name, and `limit_value`. Its subclasses are
#'     `zunpy_size_limit`, `zunpy_header_limit`, `zunpy_dims_limit` and
#'     `zunpy_members_limit`.}
#'   \item{`zunpy_io_error`}{A file or connection could not be read or
#'     written.}
#' }
#'
#' @name zunpy-conditions
#' @examples
#' e <- tryCatch(
#'   stop(structure(
#'     class = c("zunpy_parse_error", "zunpy_error", "error", "condition"),
#'     list(message = "not a .npy file", call = NULL, offset = 0)
#'   )),
#'   zunpy_error = function(e) e
#' )
#' class(e)
#' e$offset
NULL

znp_abort <- function(class, message, ..., member = NULL, call = NULL) {
  fields <- list(...)
  if (!is.null(member)) {
    fields$member <- member
  }
  stop(structure(
    class = c(class, "zunpy_error", "error", "condition"),
    c(list(message = message, call = call), fields)
  ))
}

znp_invalid_argument <- function(arg, message, call = NULL) {
  znp_abort("zunpy_invalid_argument", message, arg = arg, call = call)
}

znp_parse_error <- function(offset, message, member = NULL, call = NULL) {
  znp_abort("zunpy_parse_error", message, offset = offset, member = member,
            call = call)
}

znp_invalid_error <- function(offset, message, member = NULL, call = NULL) {
  znp_abort("zunpy_invalid_error", message, offset = offset, member = member,
            call = call)
}

znp_unsupported_type <- function(dtype, message, member = NULL, call = NULL) {
  znp_abort("zunpy_unsupported_type", message, dtype = dtype, member = member,
            call = call)
}

znp_unrepresentable <- function(message, offset = NA_real_,
                                index = NA_real_, member = NULL, call = NULL) {
  znp_abort("zunpy_unrepresentable", message, offset = offset, index = index,
            member = member, call = call)
}

znp_na_error <- function(index, message, member = NULL, call = NULL) {
  znp_abort("zunpy_na_error", message, index = index, member = member,
            call = call)
}

znp_range_error <- function(index, message, member = NULL, call = NULL) {
  znp_abort("zunpy_range_error", message, index = index, member = member,
            call = call)
}

# limit is the argument's name; the subclass follows from it.
znp_limit_error <- function(limit, limit_value, message, member = NULL,
                            call = NULL) {
  sub <- switch(limit,
    max_size = "zunpy_size_limit",
    max_header = "zunpy_header_limit",
    max_dims = "zunpy_dims_limit",
    max_members = "zunpy_members_limit",
    character()
  )
  znp_abort(c(sub, "zunpy_limit_error"), message, limit = limit,
            limit_value = limit_value, member = member, call = call)
}

znp_io_error <- function(message, call = NULL) {
  znp_abort("zunpy_io_error", message, call = call)
}
