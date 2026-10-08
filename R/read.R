# Files, URLs and connections (design sections 5, 12 and 13; roadmap Stage
# 7). Reading is bounded: a path's size is checked before anything is read,
# and any other input is read at most max_size + 1 bytes, which is enough to
# know it is too big; then the bytes go to npy_decode().

#' Read a NumPy file
#'
#' Reads a `.npy` or `.npz` file from a path, a URL or a connection, and
#' decodes it as [npy_decode()] does.
#'
#' The input is read whole into memory first, never more than `max_size`
#' bytes of it: a path whose size is above `max_size` is refused before it
#' is opened, and a URL or connection is read no further than one byte past
#' it. For a `.npz`, `names` decodes and inflates only the members named.
#'
#' A connection that is not open is opened in binary mode and closed again;
#' an open one must be binary, is read from its current position, and is
#' left open.
#'
#' @param file A path, a URL (`http://`, `https://`, `ftp://`, `ftps://` or
#'   `file://`), or a connection.
#' @inheritParams npy_decode
#' @param ... Further arguments of [npy_decode()]: `order`, `int64`, `na`,
#'   `strings`, `encoding`, `datetime`, `max_header`, `max_dims` and
#'   `max_members`.
#' @return As [npy_decode()].
#' @seealso [npy_write()]; [npy_header()] and [npy_names()] read only the
#'   header or the directory.
#' @export
#' @examples
#' f <- tempfile(fileext = ".npy")
#' npy_write(matrix(1:6, 2), f)
#' npy_read(f)
#' unlink(f)
npy_read <- function(file, ..., names = NULL, max_size = 2 * 1024^3) {
  # names after ...: before it, npy_read(f, na = "allow") would match na to
  # names partially.
  call <- sys.call()
  direct <- znp_read_direct(file, names, list(...), max_size, call)
  if (!is.null(direct)) {
    return(direct)
  }
  bytes <- znp_read_bounded(file, max_size, call)
  npy_decode(bytes, names = names, ..., max_size = max_size)
}

# The fast path of design section 16 for a path: a little-endian f8, i4 or
# c16 array that needs no permutation is read by readBin() straight into
# the result, once its header has been checked and the file's size found
# to be exactly what the header declares. NULL when it does not apply, and
# the general path reads the file.
znp_read_direct <- function(file, names, args, max_size, call) {
  if (!is.null(names) || !is.character(file) || length(file) != 1L ||
      is.na(file) || grepl("^(https?|ftps?|file)://", file, ignore.case = TRUE) ||
      !file.exists(file) || dir.exists(file) || !isTRUE(.Call(zunpy_fast_path))) {
    return(NULL)
  }
  known <- c("order", "int64", "na", "strings", "encoding", "datetime",
             "max_header", "max_dims", "max_members")
  if (!all(names(args) %in% known) || "max_members" %in% names(args)) {
    return(NULL)
  }
  max_size <- znp_check_count(max_size, "max_size", 0, 2^53, call)
  size <- file.size(file)
  if (size > max_size || size < 16) {
    return(NULL)
  }
  max_header <- if (is.null(args$max_header)) 10000 else args$max_header
  head <- znp_read_header_bytes(file, max_header, call)
  if (head[1] != as.raw(0x93)) {
    return(NULL)
  }
  h <- tryCatch(npy_header(head, max_header = max_header), zunpy_error = function(e) NULL,
                warning = function(w) NULL)
  if (is.null(h) || !is.character(h$descr) ||
      !h$descr %in% c("<f8", "<i4", "<c16")) {
    return(NULL)
  }
  k <- length(h$shape)
  order <- if (is.null(args$order)) "R" else args$order
  count <- prod(h$shape)
  max_dims <- if (is.null(args$max_dims)) 32 else args$max_dims
  if (k > max_dims || (k >= 2 && !h$fortran_order && !identical(order, "file")) ||
      any(h$shape > .Machine$integer.max) && k >= 2 ||
      size != h$data_offset + count * h$itemsize) {
    return(NULL)
  }
  na <- if (is.null(args$na)) "error" else args$na
  con <- file(file, "rb")
  on.exit(close(con), add = TRUE)
  readBin(con, "raw", h$data_offset)
  what <- switch(h$descr, "<f8" = "double", "<i4" = "integer", "<c16" = "complex")
  # readBin() takes no size for complex: its own is 16 bytes, c16's.
  value <- readBin(con, what, n = count,
                   size = if (what == "complex") NA_integer_ else h$itemsize,
                   endian = "little")
  if (length(value) != count) {
    return(NULL)
  }
  if (what == "integer" && !identical(na, "allow") && anyNA(value)) {
    i <- which(is.na(value))[1]
    znp_na_error(as.double(i), sprintf(
      "element %s is NA in R; use `na = \"allow\"` to keep it", i
    ), call = call)
  }
  if (k >= 2) {
    dim(value) <- if (h$fortran_order) h$shape else rev(h$shape)
  }
  value
}

#' Write a NumPy file
#'
#' Encodes `x` as [npy_encode()] does and writes it to a path or a
#' connection: an array, a data frame or another value as a `.npy`, a named
#' list as a `.npz`.
#'
#' A path is overwritten. A connection that is not open is opened in binary
#' mode and closed again; an open one must be binary and is left open.
#'
#' @param x The value to write; see [npy_encode()].
#' @param file A path or a connection.
#' @param ... Further arguments of [npy_encode()]: `dtype`, `order`, `na`,
#'   `encoding`, `unit` and `compress`.
#' @return `file`, invisibly.
#' @seealso [npy_read()].
#' @export
#' @examples
#' f <- tempfile(fileext = ".npz")
#' npy_write(list(a = 1:3, b = c("x", "y")), f, compress = TRUE)
#' npy_names(f)
#' str(npy_read(f))
#' unlink(f)
npy_write <- function(x, file, ...) {
  call <- sys.call()
  bytes <- npy_encode(x, ...)
  con <- file
  close_it <- FALSE
  if (!inherits(file, "connection")) {
    if (!is.character(file) || length(file) != 1L || is.na(file) || !nzchar(file)) {
      znp_invalid_argument("file", "`file` must be a single path or a connection.",
                           call = call)
    }
    # file() warns with the reason, then fails: the reason is the message.
    fail <- function(e) {
      znp_io_error(sprintf("cannot open '%s' for writing: %s", file,
                           conditionMessage(e)), call = call)
    }
    con <- tryCatch(file(file, "wb"), warning = fail, error = fail)
    close_it <- TRUE
  } else if (!isOpen(con)) {
    open(con, "wb")
    close_it <- TRUE
  } else if (!identical(summary(con)$text, "binary")) {
    znp_invalid_argument("file", "an open connection must be in binary mode",
                         call = call)
  }
  if (close_it) on.exit(close(con), add = TRUE)
  tryCatch(writeBin(bytes, con), error = function(e) {
    znp_io_error(paste0("could not write: ", conditionMessage(e)), call = call)
  })
  invisible(file)
}

# At most max_size bytes of a path, URL or connection, as one raw vector.
znp_read_bounded <- function(file, max_size, call) {
  max_size <- znp_check_count(max_size, "max_size", 0, 2^53, call)
  if (is.character(file) && length(file) == 1L && !is.na(file) &&
      !grepl("^(https?|ftps?|file)://", file, ignore.case = TRUE) &&
      file.exists(file) && !dir.exists(file)) {
    # A path: its size decides before anything is read, and one readBin()
    # reads it whole.
    size <- file.size(file)
    if (size > max_size) {
      znp_limit_error("max_size", max_size, sprintf(
        "`max_size` (%s) reached: '%s' is %s bytes",
        format(max_size, scientific = FALSE), file, format(size, scientific = FALSE)
      ), call = call)
    }
    con <- file(file, "rb")
    on.exit(close(con), add = TRUE)
    # Exactly the size: asking for more makes readBin() shrink, so copy, the
    # vector it returns.
    return(znp_read_con(con, size, call))
  }
  input <- zu_open_input(file, what = "file", prefix = "zunpy",
                         abort = function(arg, message) {
                           znp_invalid_argument(arg, message, call = call)
                         })
  if (input$close) on.exit(close(input$con), add = TRUE)
  chunks <- list()
  total <- 0
  repeat {
    b <- znp_read_con(input$con, min(65536, max_size + 1 - total), call)
    if (length(b) == 0L) break
    chunks[[length(chunks) + 1L]] <- b
    total <- total + length(b)
    if (total > max_size) {
      znp_limit_error("max_size", max_size, sprintf(
        "`max_size` (%s) reached while reading", format(max_size, scientific = FALSE)
      ), call = call)
    }
  }
  if (length(chunks) == 0L) raw() else unlist(chunks, use.names = FALSE)
}

znp_read_con <- function(con, n, call) {
  tryCatch(readBin(con, "raw", n = n), error = function(e) {
    znp_io_error(paste0("could not read input: ", conditionMessage(e)),
                 call = call)
  })
}

# The first bytes of a path, URL or connection: the prefix and the header,
# no more (npy_header() on a file). The length field says how much to read.
znp_read_header_bytes <- function(file, max_header, call) {
  input <- zu_open_input(file, what = "file", prefix = "zunpy",
                         abort = function(arg, message) {
                           znp_invalid_argument(arg, message, call = call)
                         })
  if (input$close) on.exit(close(input$con), add = TRUE)
  head <- znp_read_con(input$con, 12, call)
  if (length(head) < 10 || head[7] == as.raw(0)) {
    return(head)
  }
  n <- if (head[7] == as.raw(1)) {
    as.integer(head[9]) + 256 * as.integer(head[10])
  } else if (length(head) == 12) {
    sum(as.numeric(head[9:12]) * 256^(0:3))
  } else {
    0
  }
  prefix <- if (head[7] == as.raw(1)) 10 else 12
  # More than max_header is not read: the check phase refuses it anyway.
  want <- min(n, max_header + 1) + prefix - length(head)
  c(head, if (want > 0) znp_read_con(input$con, want, call) else raw())
}
