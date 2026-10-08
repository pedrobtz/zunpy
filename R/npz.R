# The .npz container (design section 10): a ZIP archive of .npy members.
# The directory is checked in C (src/znp_zip.c) before any member is read;
# members are inflated by zukomp with the declared size as the cap, checked
# against their CRC-32, then decoded as any .npy is.

#' The names of the arrays in a `.npz`
#'
#' Reads the directory of a `.npz` archive, without inflating or decoding
#' any member. A path, URL or connection is read into memory first, bounded
#' by `max_size`.
#'
#' @param x A raw vector holding a `.npz` file, or a path, URL or
#'   connection.
#' @param max_members The most members accepted.
#' @inheritParams npy_decode
#' @return A character vector: each member's name without its `.npy`
#'   suffix, in archive order, as `npy_decode()` names the list it returns.
#' @export
#' @examples
#' z <- npy_encode(list(a = 1:3, b = c(x = 0.5)))
#' npy_names(z)
npy_names <- function(x, max_size = 2 * 1024^3, max_members = 10000) {
  call <- sys.call()
  if (!is.raw(x)) {
    x <- znp_read_bounded(x, max_size, call)
  }
  znp_npz_members(x, max_size, max_members, call)$key
}

# The checked directory: a data frame with one row per member.
znp_npz_members <- function(x, max_size, max_members, call) {
  limits <- c(znp_check_count(max_size, "max_size", 0, 2^53, call),
              znp_check_count(max_members, "max_members", 0, 2^53, call))
  m <- .Call(zunpy_zip_members, x, limits)
  if (m$status != "ZNP_OK") {
    znp_raise_zip(m$status, m$offset, limits, call)
  }
  m$status <- NULL
  m$offset <- NULL
  m <- as.data.frame(m, stringsAsFactors = FALSE)
  m$key <- sub("\\.npy$", "", m$name)
  dup <- anyDuplicated(m$key)
  if (dup) {
    znp_invalid_error(m$data_offset[dup], sprintf(
      "the archive holds '%s' twice", m$key[dup]
    ), call = call)
  }
  m
}

znp_raise_zip <- function(status, offset, limits, call) {
  at <- sprintf(" (at byte %s)", format(offset, scientific = FALSE))
  switch(status,
    ZNP_ERR_SIZE_LIMIT = znp_limit_error("max_size", limits[[1]], paste0(
      "`max_size` reached: the archive or its declared members are larger",
      at
    ), call = call),
    ZNP_ERR_MEMBERS_LIMIT = znp_limit_error("max_members", limits[[2]], sprintf(
      "`max_members` (%s) reached", format(limits[[2]], scientific = FALSE)
    ), call = call),
    ZNP_ERR_UNSUPPORTED = znp_unsupported_type(NA_character_, paste0(
      "the archive uses a ZIP feature zunpy does not read: encryption, a ",
      "compression method other than DEFLATE, or several disks", at
    ), call = call),
    znp_parse_error(offset, paste0("not a valid .npz (ZIP) archive", at),
                    call = call)
  )
}

# Every member, or those named, decoded: a named list in archive order (or
# in the order of `names`). opts are npy_decode()'s arguments.
znp_npz_decode <- function(x, names, max_members, opts, call) {
  m <- znp_npz_members(x, opts$max_size, max_members, call)
  if (!is.null(names)) {
    if (!is.character(names) || anyNA(names) || !all(names %in% m$key)) {
      znp_invalid_argument("names", sprintf(
        "`names` must name members of the archive: %s",
        paste0("'", m$key, "'", collapse = ", ")
      ), call = call)
    }
    m <- m[match(unique(names), m$key), , drop = FALSE]
  }
  out <- vector("list", nrow(m))
  names(out) <- m$key
  for (i in seq_len(nrow(m))) {
    out[[i]] <- znp_npz_member(x, m[i, ], opts, call)
  }
  out
}

znp_npz_member <- function(x, m, opts, call) {
  key <- m$key
  # Sliced in C: x[offset + seq_len(n)] would build an index as long as the
  # member.
  payload <- .Call(zunpy_slice, x, m$data_offset, m$csize)
  if (m$method == 8L) {
    # The declared size is the cap, so an archive that lies about it stops
    # there (a zip bomb); max_output = 0 would mean no cap at all.
    payload <- tryCatch(
      zukomp::komp_decompress(payload, codec = "deflate-raw",
                              max_output = max(m$usize, 1)),
      zukomp_output_limit = function(e) {
        znp_invalid_error(0, sprintf(
          "member '%s' inflates past its declared %s bytes", key,
          format(m$usize, scientific = FALSE)
        ), member = key, call = call)
      },
      zukomp_error = function(e) {
        znp_parse_error(0, sprintf("member '%s' is not a valid DEFLATE stream",
                                   key), member = key, call = call)
      }
    )
  }
  if (length(payload) != m$usize) {
    znp_invalid_error(0, sprintf(
      "member '%s' holds %s bytes, not the %s it declares", key,
      format(length(payload), scientific = FALSE),
      format(m$usize, scientific = FALSE)
    ), member = key, call = call)
  }
  if (.Call(zunpy_crc32, payload) != m$crc) {
    znp_invalid_error(0, sprintf("member '%s' fails its CRC-32 check", key),
                      member = key, call = call)
  }
  tryCatch(
    do.call(znp_decode_npy, c(list(payload), opts, list(call = call)),
            quote = TRUE),
    zunpy_error = function(e) {
      e$member <- key
      e$message <- sprintf("in member '%s': %s", key, conditionMessage(e))
      stop(e)
    }
  )
}

# A named list as a .npz (design sections 8 and 10): each element written
# by npy_encode(), as <name>.npy, in list order.
znp_npz_encode <- function(x, dtype, compress, args, call) {
  nm <- names(x)
  if (is.null(nm) || anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(nm)) {
    znp_invalid_argument("x", paste(
      "a list is written as a .npz, and every element needs a name,",
      "non-empty and unique"
    ), call = call)
  }
  nm <- enc2utf8(nm)
  # Names become file names in the archive, which another reader may
  # extract (design section 18, Q3).
  bad <- grepl("[/\\\\]|\\x00|^\\.\\.", nm, useBytes = TRUE) | nm %in% "."
  if (any(bad)) {
    znp_invalid_argument("x", sprintf(
      "the name '%s' holds a path separator or starts with '..'",
      nm[bad][1]
    ), call = call)
  }
  if (!is.null(dtype) && (!is.list(dtype) || is.null(names(dtype)) ||
                            !all(names(dtype) %in% nm))) {
    znp_invalid_argument("dtype", paste(
      "`dtype` for a list must be a list named by its elements"
    ), call = call)
  }
  n <- length(x)
  payloads <- vector("list", n)
  crcs <- numeric(n)
  usizes <- numeric(n)
  for (i in seq_len(n)) {
    if (is.list(x[[i]]) && !is.data.frame(x[[i]])) {
      znp_unsupported_type(NA_character_, sprintf(
        "element '%s' is a list; a .npz holds no nested archive", nm[i]
      ), call = call)
    }
    bytes <- tryCatch(
      do.call(npy_encode, c(list(x[[i]], dtype = dtype[[nm[i]]]), args),
              quote = TRUE),
      zunpy_error = function(e) {
        e$member <- nm[i]
        e$message <- sprintf("in element '%s': %s", nm[i], conditionMessage(e))
        stop(e)
      }
    )
    crcs[i] <- .Call(zunpy_crc32, bytes)
    usizes[i] <- length(bytes)
    payloads[[i]] <- if (compress) {
      zukomp::komp_compress(bytes, codec = "deflate-raw", level = 6L)
    } else {
      bytes
    }
  }
  files <- if (n) paste0(nm, ".npy") else character()
  out <- .Call(zunpy_zip_build, files,
               rep(if (compress) 8L else 0L, n), crcs, usizes, payloads)
  if (is.null(out)) {
    znp_unrepresentable("the archive is too large for one raw vector",
                        call = call)
  }
  out
}
