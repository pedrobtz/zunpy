# A hand ZIP builder with every field overridable.
u16 <- function(v) as.raw(c(v %% 256, v %/% 256))
u32 <- function(v) as.raw(c(v %% 256, (v %/% 256) %% 256, (v %/% 65536) %% 256, (v %/% 16777216) %% 256))
u64 <- function(v) c(u32(v %% 2^32), u32(v %/% 2^32))
crc32 <- function(b) zunpy:::.__NAMESPACE__. # placeholder, replaced below
crc32 <- function(b) .Call(zunpy:::zunpy_crc32, b)
# members: list of list(name, data(raw, uncompressed), method=0, ...overrides)
zip_build <- function(members, comment = raw(), eocd = list(), tail = raw()) {
  out <- raw(); cd <- raw(); n <- length(members)
  for (m in members) {
    data <- m$data
    payload <- if (!is.null(m$payload)) m$payload else if (identical(m$method, 8)) zukomp::komp_compress(data, codec = "deflate-raw", level = 6L) else data
    method <- if (is.null(m$method)) 0 else m$method
    crc <- if (is.null(m$crc)) crc32(data) else m$crc
    usize <- if (is.null(m$usize)) length(data) else m$usize
    csize <- if (is.null(m$csize)) length(payload) else m$csize
    flags <- if (is.null(m$flags)) 0 else m$flags
    nm <- if (is.raw(m$name)) m$name else charToRaw(m$name)
    lname <- if (is.null(m$lname)) nm else charToRaw(m$lname)
    lextra <- if (is.null(m$lextra)) raw() else m$lextra
    cextra <- if (is.null(m$cextra)) raw() else m$cextra
    off <- if (is.null(m$offset)) length(out) else m$offset
    lcs <- if (is.null(m$lcsize)) csize else m$lcsize; lus <- if (is.null(m$lusize)) usize else m$lusize
    lcrc <- if (is.null(m$lcrc)) crc else m$lcrc
    lsig <- if (is.null(m$lsig)) c(0x50, 0x4b, 3, 4) else m$lsig
    out <- c(out, as.raw(lsig), u16(20), u16(flags), u16(method), u16(0), u16(0x21), u32(lcrc), u32(lcs), u32(lus), u16(length(lname)), u16(length(lextra)), lname, lextra, payload,
             if (!is.null(m$after)) m$after)
    ccs <- if (is.null(m$ccsize)) csize else m$ccsize; cus <- if (is.null(m$cusize)) usize else m$cusize
    coff <- if (is.null(m$coffset)) off else m$coffset
    cd <- c(cd, as.raw(c(0x50, 0x4b, 1, 2)), u16(20), u16(20), u16(flags), u16(method), u16(0), u16(0x21), u32(crc), u32(ccs), u32(cus), u16(length(nm)), u16(length(cextra)),
            u16(if (is.null(m$klen)) 0 else length(m$kcomment)), u16(if (is.null(m$disk)) 0 else m$disk), u16(0), u32(0), u32(coff), nm, cextra, if (!is.null(m$kcomment)) m$kcomment)
  }
  cdoff <- length(out)
  e <- list(disk = 0, cdisk = 0, n = n, total = n, csize = length(cd), coffset = cdoff, pre = raw())
  e[names(eocd)] <- eocd
  c(out, cd, e$pre, as.raw(c(0x50, 0x4b, 5, 6)), u16(e$disk), u16(e$cdisk), u16(e$n), u16(e$total), u32(e$csize), u32(e$coffset), u16(length(comment)), comment, tail)
}
