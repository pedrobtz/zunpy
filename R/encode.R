#' Write an R array as NumPy bytes
#'
#' Encodes an R vector, matrix or array as a `.npy` file in a raw vector.
#' The bytes are deterministic, and identical to what `numpy.save()` writes
#' for the same array.
#'
#' By default the dtype follows the R type (see [npy_dtype()]): logical to
#' `|b1`, integer to `<i4`, double to `<f8` (whole numbers too), complex to
#' `<c16`, raw to `|u1`, `integer64` to `<i8`, character and factor (its
#' labels) to `<U<n>` with `n` the most code points of any value, `Date` to
#' `<M8[D]`, `POSIXct` to `<M8[us]` (see `unit`) and `difftime` to `m8` in
#' its units (`s`, `m`, `h`, `D` or `W`). An `integer64` that [npy_decode()]
#' returned for a datetime unit without an R class is written back as its
#' `npy_dtype`.
#'
#' `dtype` chooses another dtype for one call: a numeric one for a number,
#' `"<U<n>"` or `"|S<n>"` (or `"<U"` and `"|S"` for the widest value) for a
#' string, `"<M8[s]"` and the like for a date-time. A value that does not
#' fit is an error naming its index, never a wrap, a truncation or a
#' rounding to an integer; floats round to nearest even. A date-time is
#' written when its count in the unit reads back as the same double, and
#' refused when it holds a finer fraction. Multi-byte dtypes are always
#' little-endian.
#'
#' `NA` has no place in most NumPy types. A logical `NA` is an error unless
#' `na = "allow"`, which writes `False` with a warning; an integer `NA` is
#' an error unless `na = "allow"`, which writes `-2147483648` into `<i4`
#' (what R reads back as `NA`) or NaN into a float. A double `NA` is written
#' bit for bit into `<f8`, so R reads it back as `NA` and NumPy sees a NaN.
#' A character `NA` is an error unless `na = "allow"`, which writes an
#' empty string. A date-time `NA` is NaT.
#'
#' A data frame is written as a structured array (a NumPy record array):
#' one field per column, named as the column and typed as the column would
#' be on its own, packed in column order, one record per row. `dtype` may
#' then be a named character vector giving the dtype of some columns. Row
#' names are dropped. A data frame that [npy_decode()] made from an array of
#' records with other than one dimension carries `npy_shape`, and is written
#' back with that shape. Field names must be non-empty and unique.
#'
#' A matrix or array is written in R's own (Fortran) order with
#' `fortran_order` set, which costs no copy; `order = "C"` writes C order
#' for readers that need it. `dimnames` and names are dropped. A length-1
#' vector is a 1-d array of one element: R has no 0-d array.
#'
#' @param x A logical, integer, double, complex, raw or character vector,
#'   matrix or array, a factor, a `Date`, `POSIXct` or `difftime` vector, a
#'   `bit64::integer64` vector, or a data frame of such columns.
#' @param dtype `NULL` for the default of the R type; for a data frame, a
#'   named character vector of dtypes for some of its columns; else a NumPy
#'   dtype string: `"|b1"`, `"|i1"`, `"<i2"`, `"<i4"`, `"<i8"`, `"|u1"`, `"<u2"`,
#'   `"<u4"`, `"<u8"`, `"<f2"`, `"<f4"`, `"<f8"`, `"<c8"`, `"<c16"`,
#'   `"<U<n>"`, `"|S<n>"`, `"<M8[<unit>]"` or `"<m8[<unit>]"`.
#' @param order `"F"` (R's order) or `"C"` (NumPy's default).
#' @param na `"error"` or `"allow"`; see Details.
#' @param encoding For `|S<n>` output: `"UTF-8"` writes each string's UTF-8
#'   bytes, `"latin1"` converts to Latin-1 first (a character with no
#'   Latin-1 form is an error), and `"bytes"` writes the bytes as they are.
#' @param unit The unit for `POSIXct`: `"us"` (the default), `"ns"`, `"ms"`
#'   or `"s"`.
#' @return A raw vector holding a whole `.npy` file.
#' @seealso [npy_decode()] to read it back.
#' @export
#' @examples
#' x <- matrix(c(1.5, 2, 3, 4), 2)
#' bytes <- npy_encode(x)
#' identical(npy_decode(bytes), x)
#' npy_header(bytes)$descr
#' npy_header(npy_encode(1:3, dtype = "|u1"))$descr
npy_encode <- function(x, dtype = NULL, order = c("F", "C"),
                       na = c("error", "allow"),
                       encoding = c("UTF-8", "latin1", "bytes"),
                       unit = c("us", "ns", "ms", "s")) {
  call <- sys.call()
  order <- znp_match(order, c("F", "C"), "order", call)
  na <- znp_match(na, c("error", "allow"), "na", call)
  encoding <- znp_match(encoding, c("UTF-8", "latin1", "bytes"), "encoding",
                        call)
  unit <- znp_match(unit, c("us", "ns", "ms", "s"), "unit", call)
  if (is.data.frame(x)) {
    return(znp_encode_records(x, dtype, order, na, encoding, unit, call))
  }
  source <- znp_source_type(x, call)
  descr <- if (is.null(dtype)) znp_default_dtype(source, x, unit) else dtype
  spec <- znp_target_spec(descr, source, x, call)
  shape <- if (is.null(dim(x))) length(x) else dim(x)
  if (length(shape) > 64) {
    znp_invalid_argument("x", "`x` has more than 64 dimensions.", call = call)
  }
  value <- znp_prepare(x, source, spec, na, encoding, call)
  opts <- as.integer(c(order == "C", na == "allow",
                       source %in% c("integer64", "integer64_time")))
  res <- .Call(zunpy_encode, value, spec, as.double(shape), opts)
  if (spec[[1]] %in% c("U", "S") && identical(spec[[2]], -1L)) {
    descr <- npy_header(res$value)$descr
  }
  switch(res$status,
    ZNP_OK = NULL,
    ZNP_WRITE_INVALID = znp_invalid_argument("x", sprintf(
      "element %s is not valid UTF-8", format(res$index, scientific = FALSE)
    ), call = call),
    ZNP_WRITE_NA = znp_na_error(res$index, sprintf(
      "element %s is NA, which dtype '%s' cannot hold; see `na`",
      format(res$index, scientific = FALSE), descr
    ), call = call),
    ZNP_WRITE_RANGE = znp_range_error(res$index, sprintf(
      "element %s does not fit dtype '%s'",
      format(res$index, scientific = FALSE), descr
    ), call = call),
    znp_unrepresentable("the array is too large for one raw vector",
                        call = call)
  )
  if (res$replaced > 0) {
    znp_warn("zunpy_na_replaced", sprintf(
      "%s logical NA written as False", format(res$replaced, scientific = FALSE)
    ), call = call)
  }
  res$value
}

#' The NumPy dtype for an R value
#'
#' The dtype string [npy_encode()] writes for `x` when no `dtype` is given.
#'
#' @param x An R value.
#' @return A string such as `"<f8"`.
#' @export
#' @examples
#' npy_dtype(1:3)
#' npy_dtype(c(TRUE, FALSE))
#' npy_dtype(matrix(0, 2, 2))
npy_dtype <- function(x) {
  znp_default_dtype(znp_source_type(x, sys.call()), x, "us")
}

# The kind of R value, for the type table of design section 7.1.
znp_source_type <- function(x, call) {
  if (inherits(x, "integer64")) {
    d <- attr(x, "npy_dtype")
    if (is.character(d) && length(d) == 1L && grepl("^<[Mm]8\\[", d)) {
      return("integer64_time")
    }
    return("integer64")
  }
  if (is.factor(x)) return("factor")
  if (inherits(x, "Date")) return("Date")
  if (inherits(x, "POSIXct")) return("POSIXct")
  if (inherits(x, "difftime")) return("difftime")
  cls <- setdiff(class(x), c("matrix", "array", "numeric", "integer",
                             "logical", "complex", "raw", "character"))
  if (length(cls) > 0 || is.object(x) && !is.matrix(x) && !is.array(x)) {
    znp_unsupported_type(NA_character_, sprintf(
      "cannot write an object of class '%s' yet", class(x)[1]
    ), call = call)
  }
  switch(typeof(x),
    logical = "logical",
    integer = "integer",
    double = "double",
    complex = "complex",
    raw = "raw",
    character = "character",
    znp_unsupported_type(NA_character_, sprintf(
      "cannot write a value of type '%s'", typeof(x)
    ), call = call)
  )
}

znp_difftime_units <- c(secs = "s", mins = "m", hours = "h", days = "D",
                         weeks = "W")

znp_default_dtype <- function(source, x, unit) {
  switch(source,
    logical = "|b1", integer = "<i4", double = "<f8", complex = "<c16",
    raw = "|u1", integer64 = "<i8",
    integer64_time = attr(x, "npy_dtype"),
    character = , factor = "<U",
    Date = "<M8[D]",
    POSIXct = sprintf("<M8[%s]", unit),
    difftime = sprintf("<m8[%s]", znp_difftime_units[[units(x)]])
  )
}

# Which dtypes each R type can reach (design section 7.1, dtype =), as
# list(kind, width, unit, scale) for C. A width of -1 asks for the widest
# value.
znp_target_spec <- function(descr, source, x, call) {
  numeric <- c("|i1", "<i2", "<i4", "<i8", "|u1", "<u2", "<u4", "<u8",
               "<f2", "<f4", "<f8")
  bad <- function(allowed) {
    znp_invalid_argument("dtype", sprintf(
      "`dtype` for a %s value must be %s.", source, allowed
    ), call = call)
  }
  if (!is.character(descr) || length(descr) != 1L || is.na(descr)) {
    bad("one string")
  }
  if (source %in% c("character", "factor")) {
    m <- regmatches(descr, regexec("^(<U|\\|S)([0-9]*)$", descr))[[1]]
    if (length(m) == 0L) bad('"<U", "<U<n>", "|S" or "|S<n>"')
    width <- if (nzchar(m[3])) as.numeric(m[3]) else -1
    if (width > .Machine$integer.max / 4) bad("a dtype narrower than 2^29")
    return(list(substr(descr, 2, 2), as.integer(width), "", 0))
  }
  if (source %in% c("Date", "POSIXct", "difftime", "integer64_time")) {
    m <- regmatches(descr, regexec("^<([Mm])8\\[([A-Za-z]+)\\]$", descr))[[1]]
    kind <- if (length(m)) m[2] else ""
    u <- if (length(m)) m[3] else ""
    # Ticks per R unit: days for Date, seconds for POSIXct, the difftime's
    # own units otherwise.
    scale <- switch(source,
      Date = if (kind == "M" && u == "D") 1,
      POSIXct = if (kind == "M") c(s = 1, ms = 1e3, us = 1e6, ns = 1e9)[u],
      difftime = if (kind == "m") {
        # Its own unit as it is; s, ms, us and ns from seconds.
        own <- znp_difftime_units[[units(x)]]
        if (u == own) 1 else c(s = 1, ms = 1e3, us = 1e6, ns = 1e9)[u]
      },
      integer64_time = if (kind %in% c("M", "m") &&
                             u %in% c("Y", "M", "W", "D", "h", "m", "s", "ms",
                                      "us", "ns", "ps", "fs", "as")) 0
    )
    if (is.null(scale) || length(scale) != 1L || is.na(scale)) {
      bad(switch(source,
        Date = '"<M8[D]"',
        POSIXct = '"<M8[s]", "<M8[ms]", "<M8[us]" or "<M8[ns]"',
        difftime = 'an m8 dtype in its own units, or in s, ms, us or ns for seconds',
        integer64_time = "a datetime64 or timedelta64 dtype"
      ))
    }
    return(list(kind, 8L, u, as.double(scale)))
  }
  allowed <- switch(source,
    logical = c("|b1", numeric),
    integer = c("|b1", numeric),
    double = numeric,
    complex = c("<c8", "<c16"),
    raw = "|u1",
    integer64 = c("<i8", "<u8")
  )
  if (!descr %in% allowed) {
    bad(paste0("one of ", paste0('"', allowed, '"', collapse = ", ")))
  }
  list(substr(descr, 2, 2), as.integer(substring(descr, 3)), "", 0)
}

# The bare vector C writes: attributes dropped, strings in the bytes they
# are written as, NA handled where R must do it.
znp_prepare <- function(x, source, spec, na, encoding, call) {
  if (source %in% c("integer64", "integer64_time")) {
    return(as.double(unclass(x)))
  }
  if (source == "factor") {
    x <- as.character(x)
  }
  if (source %in% c("character", "factor")) {
    x <- as.vector(x)
    miss <- which(is.na(x))
    if (length(miss) > 0) {
      if (na == "error") {
        znp_na_error(as.double(miss[1]), sprintf(
          "element %s is NA, which a string dtype cannot hold; see `na`",
          miss[1]
        ), call = call)
      }
      x[miss] <- ""
    }
    if (spec[[1]] == "U" || encoding == "UTF-8") {
      x <- enc2utf8(x)
    } else if (encoding == "latin1") {
      y <- iconv(x, from = "", to = "latin1", toRaw = FALSE)
      bad <- which(is.na(y) & !is.na(x))
      if (length(bad) > 0) {
        znp_range_error(as.double(bad[1]), sprintf(
          "element %s has a character with no Latin-1 form", bad[1]
        ), call = call)
      }
      x <- y
      Encoding(x) <- "bytes"
    }
    return(x)
  }
  if (source == "difftime" && spec[[3]] != znp_difftime_units[[units(x)]]) {
    # In seconds first: an m8[ms] from a difftime in minutes.
    x <- as.double(x, units = "secs")
  }
  x <- unclass(x)
  attributes(x) <- NULL
  if (source %in% c("Date", "POSIXct", "difftime")) {
    # A Date may be stored as integer.
    x <- as.double(x)
  }
  x
}

# A data frame as a structured array (design section 7.3).
znp_encode_records <- function(x, dtype, order, na, encoding, unit, call) {
  nm <- names(x)
  if (is.null(nm) || anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(nm)) {
    znp_invalid_argument("x", paste(
      "every column of a data frame needs a name, non-empty and unique,",
      "to be a field"
    ), call = call)
  }
  nm <- enc2utf8(nm)
  if (length(x) > 1024) {
    znp_invalid_argument("x", "a data frame of more than 1,024 columns",
                         call = call)
  }
  if (!is.null(dtype) && (!is.character(dtype) || is.null(names(dtype)) ||
                            !all(names(dtype) %in% nm))) {
    znp_invalid_argument("dtype", paste(
      "`dtype` for a data frame must be a character vector named by its",
      "columns"
    ), call = call)
  }
  specs <- vector("list", length(x))
  cols <- vector("list", length(x))
  int64s <- logical(length(x))
  for (j in seq_along(x)) {
    col <- x[[j]]
    if (is.list(col) || length(dim(col)) > 1) {
      znp_unsupported_type(NA_character_, sprintf(
        "column '%s' is a %s; a field holds one value per row", nm[j],
        if (is.list(col)) "list" else "matrix"
      ), call = call)
    }
    source <- znp_source_type(col, call)
    descr <- if (!is.null(dtype) && nm[j] %in% names(dtype)) {
      dtype[[nm[j]]]
    } else {
      znp_default_dtype(source, col, unit)
    }
    specs[[j]] <- znp_target_spec(descr, source, col, call)
    cols[[j]] <- znp_prepare(col, source, specs[[j]], na, encoding, call)
    int64s[j] <- source %in% c("integer64", "integer64_time")
  }
  shape <- attr(x, "npy_shape")
  if (is.null(shape)) {
    shape <- nrow(x)
  } else if (!is.numeric(shape) || length(shape) > 64 || prod(shape) != nrow(x)) {
    znp_invalid_argument("x", "`npy_shape` does not match the rows", call = call)
  }
  opts <- as.integer(c(order == "C", na == "allow"))
  res <- .Call(zunpy_encode_records, cols, specs, nm, as.double(shape), opts,
               int64s)
  if (res$status != "ZNP_OK") {
    col <- if (!is.na(res$column)) sprintf(" in column '%s'", nm[res$column]) else ""
    switch(res$status,
      ZNP_WRITE_NA = znp_na_error(res$index, sprintf(
        "row %s%s is NA, which its dtype cannot hold; see `na`",
        format(res$index, scientific = FALSE), col
      ), call = call),
      ZNP_WRITE_RANGE = znp_range_error(res$index, sprintf(
        "row %s%s does not fit its dtype", format(res$index, scientific = FALSE),
        col
      ), call = call),
      ZNP_WRITE_INVALID = znp_invalid_argument("x", sprintf(
        "row %s%s is not valid UTF-8", format(res$index, scientific = FALSE), col
      ), call = call),
      znp_unrepresentable("the array is too large for one raw vector",
                          call = call)
    )
  }
  if (res$replaced > 0) {
    znp_warn("zunpy_na_replaced", sprintf(
      "%s logical NA written as False", format(res$replaced, scientific = FALSE)
    ), call = call)
  }
  res$value
}
