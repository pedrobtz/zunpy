#' Read a NumPy array from bytes
#'
#' Decodes a `.npy` file already in memory into an R vector, matrix or
#' array. The header is parsed and checked whole, and the declared shape
#' compared with the bytes present, before anything is allocated.
#'
#' Types map as follows: `b1` to logical; `i1`, `u1`, `i2`, `u2` and `i4`
#' to integer; `u4`, `f2`, `f4` and `f8` to double; `i8` and `u8` to double,
#' or to `integer64` with `int64 = "integer64"`; `c8` and `c16` to complex.
#' Every value is converted exactly or refused: an `i4` of `-2^31` is R's
#' `NA_integer_`, so it is an error unless `na = "allow"`, and a 64-bit
#' integer beyond `2^53` in magnitude, which a double cannot hold exactly,
#' is an error unless `int64 = "integer64"`. Structured dtypes are not
#' supported yet.
#'
#' Strings: `S<n>` (bytes) and `U<n>` (code points) become character
#' vectors in UTF-8, with the trailing NULs NumPy pads with removed. `S<n>`
#' bytes are decoded as `encoding` says, and `strings = "raw"` returns each
#' as a raw vector instead. A NUL inside a value cannot live in an R string
#' and is an error. `V<n>` becomes a list of raw vectors.
#'
#' Dates and times: `M8[D]` becomes `Date`; `M8[s]`, `M8[ms]`, `M8[us]` and
#' `M8[ns]` become `POSIXct` in UTC; `m8` becomes `difftime` in days,
#' hours, minutes, weeks or seconds (`ms`, `us` and `ns` scaled to
#' seconds). NaT is `NA`. A double cannot hold every nanosecond since 1970,
#' so `M8[ns]` is the nearest double; `datetime = "integer64"` keeps the
#' counts exactly. Units with no R class (`Y`, `M` and finer than `ns`) are
#' returned as `integer64` counts either way. Such an `integer64` carries
#' the dtype in its `npy_dtype` attribute, and [npy_encode()] writes it back
#' as that dtype.
#'
#' A 0-d array becomes a length-1 vector and a 1-d array a vector, both
#' without `dim`. NumPy's default C order (last index fastest) is permuted
#' into R's column-major order, so that `a[i, j]` in R is `a[i-1, j-1]` in
#' Python; `order = "file"` skips the permutation and returns the array with
#' its dimensions reversed, its memory identical to the file's.
#'
#' @param x A raw vector holding a whole `.npy` file.
#' @param order `"R"` to index as NumPy does, or `"file"` to keep the
#'   file's memory order.
#' @param int64 `"double"` or `"integer64"` (needs the bit64 package to be
#'   useful) for `i8` and `u8`.
#' @param na `"error"` or `"allow"`: whether a value that is `NA` in R is
#'   refused.
#' @param strings `"character"` or `"raw"`, for `S<n>`.
#' @param encoding The encoding of `S<n>` bytes: `"UTF-8"` (validated),
#'   `"latin1"` (converted to UTF-8) or `"bytes"` (left as bytes).
#' @param datetime `"convert"` to `Date`, `POSIXct` and `difftime`, or
#'   `"integer64"` for the counts as they are.
#' @param max_size The largest input accepted, in bytes.
#' @param max_header The largest header accepted, in bytes; NumPy's own
#'   default.
#' @param max_dims The most dimensions accepted, at most 64.
#' @return A vector, matrix or array.
#' @seealso [npy_header()] for the header alone; [zunpy-conditions] for the
#'   errors.
#' @export
#' @examples
#' # A 2 x 3 little-endian double matrix in C order, as numpy.save() writes it.
#' dict <- "{'descr': '<f8', 'fortran_order': False, 'shape': (2, 3), }"
#' pad <- (64 - (10 + nchar(dict) + 1) %% 64) %% 64
#' header <- c(charToRaw(dict), rep(charToRaw(" "), pad), charToRaw("\n"))
#' x <- c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0)),
#'        as.raw(c(length(header), 0)), header,
#'        writeBin(as.double(0:5), raw(), size = 8, endian = "little"))
#' npy_decode(x)
npy_decode <- function(x, order = c("R", "file"),
                       int64 = c("double", "integer64"),
                       na = c("error", "allow"),
                       strings = c("character", "raw"),
                       encoding = c("UTF-8", "latin1", "bytes"),
                       datetime = c("convert", "integer64"),
                       max_size = 2 * 1024^3, max_header = 10000,
                       max_dims = 32) {
  call <- sys.call()
  znp_check_raw(x, call = call)
  order <- znp_match(order, c("R", "file"), "order", call)
  int64 <- znp_match(int64, c("double", "integer64"), "int64", call)
  na <- znp_match(na, c("error", "allow"), "na", call)
  strings <- znp_match(strings, c("character", "raw"), "strings", call)
  encoding <- znp_match(encoding, c("UTF-8", "latin1", "bytes"), "encoding",
                        call)
  datetime <- znp_match(datetime, c("convert", "integer64"), "datetime", call)
  limits <- znp_limits(max_size, max_header, max_dims, 1024, call = call)
  opts <- c(order == "file", int64 == "integer64", na == "allow",
            strings == "raw", match(encoding, c("UTF-8", "latin1", "bytes")) - 1,
            datetime == "integer64")
  res <- .Call(zunpy_decode, x, limits, as.integer(opts))
  if (res$status != "ZNP_OK") {
    znp_raise_status(res$status, res$offset, x, limits, index = res$index,
                     descr = res$descr, call = call)
  }
  znp_header_warnings(res, call)
  if (is.na(res$descr)) {
    return(znp_records(res$value, res$shape, int64, datetime))
  }
  znp_classify(res$value, res$descr, int64, datetime)
}

# A structured array as a data frame (design section 6.3): one column per
# field, or per element of a subarray field; one row per record, in R's
# order; `npy_shape` when the array is not 1-d.
znp_records <- function(value, shape, int64, datetime) {
  cols <- Map(function(col, descr) znp_classify(col, descr, int64, datetime),
              value[[1]], value[[3]])
  names(cols) <- value[[2]]
  n <- if (length(shape)) prod(shape) else 1
  df <- structure(cols, class = "data.frame", row.names = c(NA_integer_, -n))
  if (length(shape) != 1L) {
    attr(df, "npy_shape") <- shape
  }
  df
}

# The R class a dtype reads as (design section 6.1, D7). value is the bare
# vector the build phase made.
znp_classify <- function(value, descr, int64, datetime) {
  kind <- substr(descr, 2, 2)
  if (kind %in% c("i", "u") && substring(descr, 3) == "8" &&
      int64 == "integer64") {
    class(value) <- "integer64"
    return(value)
  }
  if (!kind %in% c("M", "m")) {
    return(value)
  }
  unit <- sub("^.*\\[(.*)\\]$", "\\1", descr)
  scaled <- datetime == "convert" &&
    (unit %in% c("D", "s", "ms", "us", "ns") ||
       kind == "m" && unit %in% c("m", "h", "W"))
  if (!scaled) {
    attr(value, "npy_dtype") <- descr
    class(value) <- "integer64"
    return(value)
  }
  if (kind == "M" && unit == "D") {
    return(structure(value, class = "Date"))
  }
  if (kind == "M") {
    return(structure(value, class = c("POSIXct", "POSIXt"), tzone = "UTC"))
  }
  units <- switch(unit, D = "days", h = "hours", m = "mins", W = "weeks",
                  "secs")
  structure(value, class = "difftime", units = units)
}

#' Read the header of a NumPy array
#'
#' Parses and checks a `.npy` header without reading its data, for a raw
#' vector that holds at least the header.
#'
#' @param x A raw vector holding a `.npy` file, or its first bytes.
#' @inheritParams npy_decode
#' @return A list: `version`, the format version as a string such as
#'   `"1.0"`; `descr`, the dtype as a string such as `"<f8"`, or for a
#'   structured dtype a data frame with columns `name`, `title`, `descr`,
#'   `offset` and `shape`; `fortran_order`; `shape`, a numeric vector,
#'   empty for a 0-d array; `itemsize`, bytes per element; and
#'   `data_offset`, where the data starts.
#' @export
#' @examples
#' dict <- "{'descr': '<i4', 'fortran_order': False, 'shape': (3,), }"
#' pad <- (64 - (10 + nchar(dict) + 1) %% 64) %% 64
#' header <- c(charToRaw(dict), rep(charToRaw(" "), pad), charToRaw("\n"))
#' x <- c(as.raw(c(0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 1, 0)),
#'        as.raw(c(length(header), 0)), header)
#' npy_header(x)
npy_header <- function(x, max_header = 10000) {
  call <- sys.call()
  p <- znp_header_check(x, max_size = 2^53, max_header = max_header,
                        max_dims = 64, header_only = TRUE, call = call)
  znp_header_warnings(p, call)
  descr <- p$descr
  if (!is.null(p$fields)) {
    f <- p$fields
    descr <- data.frame(name = f$name, title = f$title, descr = f$descr,
                        offset = f$offset, stringsAsFactors = FALSE)
    descr$shape <- f$shape
  }
  list(
    version = paste(p$version, collapse = "."),
    descr = descr,
    fortran_order = p$fortran_order,
    shape = p$shape,
    itemsize = p$itemsize,
    data_offset = p$data_offset
  )
}

znp_header_warnings <- function(p, call) {
  if (isTRUE(p$native_order)) {
    znp_warn("zunpy_byte_order", paste(
      "the dtype gives no byte order or a native one ('='), which NumPy",
      "never writes; it is read as little-endian"
    ), call = call)
  }
  if (isFALSE(p$align64)) {
    znp_warn("zunpy_alignment",
             "the data starts at a multiple of 16 bytes but not of 64",
             call = call)
  }
}
