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
#'     record fields overlap or share a name, a string is not valid in its
#'     encoding (a surrogate in `U`, bytes that are not UTF-8 in `S`), or a
#'     checksum does not match. Carries `offset`, and `index` for a value.}
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
#' Warnings inherit from `zunpy_warning`: `zunpy_byte_order` when a dtype
#' gives its byte order as native (`=`) or not at all, which NumPy never
#' writes and which is read as little-endian; and `zunpy_alignment` when
#' the data starts at a multiple of 16 bytes but not of 64, as files from
#' NumPy before 1.14 and from other writers do.
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

znp_invalid_error <- function(offset, message, index = NA_real_,
                              member = NULL, call = NULL) {
  znp_abort("zunpy_invalid_error", message, offset = offset, index = index,
            member = member, call = call)
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

znp_warn <- function(class, message, call = NULL) {
  warning(structure(
    class = c(class, "zunpy_warning", "warning", "condition"),
    list(message = message, call = call)
  ))
}

# A status name from C -> a condition, by the enumerator's name. offset is
# the 0-based byte offset of the fault in x. Statuses that only misuse of
# the internal API can cause map to the bare zunpy_error: still catchable,
# never mistaken for a fault in the input.
# index (1-based, file order) and descr come from the build phase.
znp_raise_status <- function(status, offset, x, limits, member = NULL,
                             index = NA_real_, descr = NA_character_,
                             call = NULL) {
  parse <- c(
    ZNP_ERR_MAGIC = "not a .npy file: the magic string is wrong",
    ZNP_ERR_VERSION = "unsupported .npy format version",
    ZNP_ERR_TRUNCATED = "the input ends early",
    ZNP_ERR_TRAILING = "bytes follow the declared data",
    ZNP_ERR_ALIGN = "the data does not start at a multiple of 16 bytes",
    ZNP_ERR_ENCODING = "the header holds an invalid or NUL character",
    ZNP_ERR_SYNTAX = "the header is not a valid literal",
    ZNP_ERR_DEPTH = "the header is nested too deeply",
    ZNP_ERR_KEY = "the header's keys are not descr, fortran_order and shape",
    ZNP_ERR_TYPE = "a header value has the wrong type",
    ZNP_ERR_DESCR = "the dtype is not valid",
    ZNP_ERR_SHAPE = "a dimension is negative or too large"
  )
  at <- sprintf(" (at byte %s)", format(offset, scientific = FALSE))
  if (status %in% names(parse)) {
    znp_parse_error(offset, paste0(parse[[status]], at), member = member,
                    call = call)
  }
  limit <- c(
    ZNP_ERR_SIZE_LIMIT = "max_size",
    ZNP_ERR_HEADER_LIMIT = "max_header",
    ZNP_ERR_DIMS_LIMIT = "max_dims",
    ZNP_ERR_FIELDS_LIMIT = "max_fields"
  )
  if (status %in% names(limit)) {
    l <- limit[[status]]
    value <- limits[[match(l, c("max_size", "max_header", "max_dims",
                                "max_fields"))]]
    znp_limit_error(l, value, sprintf(
      "`%s` (%s) reached%s", l, format(value, scientific = FALSE), at
    ), member = member, call = call)
  }
  switch(status,
    ZNP_BUILD_NA = znp_na_error(
      index, sprintf("element %s is NA in R; use `na = \"allow\"` to keep it",
                     format(index, scientific = FALSE)),
      member = member, call = call
    ),
    ZNP_BUILD_UNREPRESENTABLE = znp_unrepresentable(
      if (is.na(index)) {
        "a dimension is larger than R's 2^31 - 1"
      } else {
        sprintf(
          "element %s cannot be held in R: beyond 2^53, or a string with NUL",
          format(index, scientific = FALSE)
        )
      },
      offset = offset, index = index, member = member, call = call
    ),
    ZNP_BUILD_INVALID = znp_invalid_error(
      offset, sprintf("element %s is not valid in its encoding",
                      format(index, scientific = FALSE)),
      index = index, member = member, call = call
    ),
    ZNP_BUILD_NOT_YET = znp_unsupported_type(
      descr, sprintf("dtype '%s' is not supported yet", descr),
      member = member, call = call
    ),
    ZNP_ERR_LAYOUT = znp_invalid_error(
      offset, paste0("the record fields overlap or do not fit", at),
      member = member, call = call
    ),
    ZNP_ERR_UNSUPPORTED = {
      dtype <- znp_quoted_at(x, offset)
      znp_unsupported_type(dtype, paste0(
        "unsupported dtype",
        if (!is.na(dtype)) sprintf(" '%s'", dtype),
        at
      ), member = member, call = call)
    },
    znp_abort(character(), paste0("internal error: ", status),
              status = status, call = call)
  )
}
