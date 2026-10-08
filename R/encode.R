#' Write an R array as NumPy bytes
#'
#' Encodes an R vector, matrix or array as a `.npy` file in a raw vector.
#' The bytes are deterministic, and identical to what `numpy.save()` writes
#' for the same array.
#'
#' By default the dtype follows the R type (see [npy_dtype()]): logical to
#' `|b1`, integer to `<i4`, double to `<f8` (whole numbers too), complex to
#' `<c16`, raw to `|u1` and `integer64` to `<i8`. `dtype` chooses another
#' numeric dtype for one call: a value that does not fit it is an error
#' naming its index, never a wrap or a rounding to an integer; floats round
#' to nearest even. Multi-byte dtypes are always little-endian.
#'
#' `NA` has no place in most NumPy types. A logical `NA` is an error unless
#' `na = "allow"`, which writes `False` with a warning; an integer `NA` is
#' an error unless `na = "allow"`, which writes `-2147483648` into `<i4`
#' (what R reads back as `NA`) or NaN into a float. A double `NA` is written
#' bit for bit into `<f8`, so R reads it back as `NA` and NumPy sees a NaN.
#'
#' A matrix or array is written in R's own (Fortran) order with
#' `fortran_order` set, which costs no copy; `order = "C"` writes C order
#' for readers that need it. `dimnames` and names are dropped. A length-1
#' vector is a 1-d array of one element: R has no 0-d array.
#'
#' @param x A logical, integer, double, complex or raw vector, matrix or
#'   array, or a `bit64::integer64` vector.
#' @param dtype `NULL` for the default of the R type, or a NumPy dtype
#'   string: `"|b1"`, `"|i1"`, `"<i2"`, `"<i4"`, `"<i8"`, `"|u1"`, `"<u2"`,
#'   `"<u4"`, `"<u8"`, `"<f2"`, `"<f4"`, `"<f8"`, `"<c8"` or `"<c16"`.
#' @param order `"F"` (R's order) or `"C"` (NumPy's default).
#' @param na `"error"` or `"allow"`; see Details.
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
                       na = c("error", "allow")) {
  call <- sys.call()
  order <- znp_match(order, c("F", "C"), "order", call)
  na <- znp_match(na, c("error", "allow"), "na", call)
  source <- znp_source_type(x, call)
  descr <- if (is.null(dtype)) znp_default_dtype(source) else dtype
  spec <- znp_target_spec(descr, source, call)
  shape <- if (is.null(dim(x))) length(x) else dim(x)
  if (length(shape) > 64) {
    znp_invalid_argument("x", "`x` has more than 64 dimensions.", call = call)
  }
  opts <- as.integer(c(order == "C", na == "allow", source == "integer64"))
  res <- .Call(zunpy_encode, znp_strip(x), spec, as.double(shape), opts)
  switch(res$status,
    ZNP_OK = NULL,
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
  znp_default_dtype(znp_source_type(x, sys.call()))
}

# The kind of R value, for the type table of design section 7.1. Classed
# values other than integer64 and plain matrices and arrays arrive in later
# stages.
znp_source_type <- function(x, call) {
  if (inherits(x, "integer64")) {
    return("integer64")
  }
  cls <- setdiff(class(x), c("matrix", "array", "numeric", "integer",
                             "logical", "complex", "raw"))
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
    znp_unsupported_type(NA_character_, sprintf(
      "cannot write a value of type '%s'", typeof(x)
    ), call = call)
  )
}

znp_default_dtype <- function(source) {
  c(logical = "|b1", integer = "<i4", double = "<f8", complex = "<c16",
    raw = "|u1", integer64 = "<i8")[[source]]
}

# Which dtypes each R type can reach (design section 7.1, dtype =).
znp_target_spec <- function(descr, source, call) {
  numeric <- c("|i1", "<i2", "<i4", "<i8", "|u1", "<u2", "<u4", "<u8",
               "<f2", "<f4", "<f8")
  allowed <- switch(source,
    logical = c("|b1", numeric),
    integer = c("|b1", numeric),
    double = numeric,
    complex = c("<c8", "<c16"),
    raw = "|u1",
    integer64 = c("<i8", "<u8")
  )
  if (!is.character(descr) || length(descr) != 1L || is.na(descr) ||
      !descr %in% allowed) {
    znp_invalid_argument("dtype", sprintf(
      "`dtype` for a %s value must be one of %s.", source,
      paste0('"', allowed, '"', collapse = ", ")
    ), call = call)
  }
  list(substr(descr, 2, 2), as.integer(substring(descr, 3)))
}

# The bare vector: attributes other than the type are not written.
znp_strip <- function(x) {
  if (inherits(x, "integer64")) {
    return(unclass(x))
  }
  attributes(x) <- NULL
  x
}
