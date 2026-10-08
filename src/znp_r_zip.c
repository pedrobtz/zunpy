/* .Call glue for .npz (design 10): the member table, CRC-32, and building
   an archive. Statuses come back by name; R raises. */
#include <string.h>

#include <zufast/utf8.h>

#include "znp_r.h"
#include "znp_zip.h"

/* limits: c(max_size, max_members). Returns list(status, offset, name,
   method, crc, csize, usize, data_offset). A name is UTF-8 when its entry
   says so or when it is valid UTF-8, else Latin-1. */
SEXP zunpy_zip_members(SEXP x, SEXP limits)
{
    znp_zip_limits lim;
    lim.max_size = (uint64_t)REAL(limits)[0];
    lim.max_members = (uint64_t)REAL(limits)[1];
    const uint8_t *data = RAW(x);
    size_t size = (size_t)XLENGTH(x);
    znp_fault fault;
    uint64_t count = 0, n = 0;
    znp_member *m = NULL;
    znp_status st = znp_zip_count(data, size, &lim, &count, &fault);
    if (st == ZNP_OK) {
        m = (znp_member *)(void *)R_alloc(count ? (size_t)count : 1, sizeof(znp_member));
        st = znp_zip_check(data, size, &lim, m, count, &n, &fault);
    }

    const char *names[] = {"status", "offset", "name", "method", "crc",
                           "csize", "usize", "data_offset"};
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 8));
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, 8));
    for (int i = 0; i < 8; i++)
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nm);
    SET_VECTOR_ELT(out, 0, Rf_mkString(znp_status_name(st)));
    SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)fault.offset));
    if (st != ZNP_OK) {
        UNPROTECT(2);
        return out;
    }
    SEXP name = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)n));
    SEXP method = PROTECT(Rf_allocVector(INTSXP, (R_xlen_t)n));
    SEXP crc = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t)n));
    SEXP csize = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t)n));
    SEXP usize = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t)n));
    SEXP off = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t)n));
    for (uint64_t i = 0; i < n; i++) {
        int utf8 = (m[i].flags & 0x0800) || zuf_utf8_valid(m[i].name, m[i].name_len);
        SET_STRING_ELT(name, (R_xlen_t)i,
                       Rf_mkCharLenCE(m[i].name, (int)m[i].name_len,
                                      utf8 ? CE_UTF8 : CE_LATIN1));
        INTEGER(method)[i] = m[i].method;
        REAL(crc)[i] = (double)m[i].crc;
        REAL(csize)[i] = (double)m[i].csize;
        REAL(usize)[i] = (double)m[i].usize;
        REAL(off)[i] = (double)m[i].data_offset;
    }
    SET_VECTOR_ELT(out, 2, name);
    SET_VECTOR_ELT(out, 3, method);
    SET_VECTOR_ELT(out, 4, crc);
    SET_VECTOR_ELT(out, 5, csize);
    SET_VECTOR_ELT(out, 6, usize);
    SET_VECTOR_ELT(out, 7, off);
    UNPROTECT(8);
    return out;
}

/* x[offset + 1:n] as a new raw vector; the directory check has bounded
   both by the length of x. */
SEXP zunpy_slice(SEXP x, SEXP offset, SEXP n)
{
    double off = REAL(offset)[0], len = REAL(n)[0];
    if (off < 0 || len < 0 || off + len > (double)XLENGTH(x))
        return R_NilValue;
    SEXP out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t)len));
    if (len > 0)
        memcpy(RAW(out), RAW(x) + (size_t)off, (size_t)len);
    UNPROTECT(1);
    return out;
}

SEXP zunpy_crc32(SEXP x)
{
    return Rf_ScalarReal((double)znp_crc32(RAW(x), (size_t)XLENGTH(x)));
}

/* names (UTF-8), methods, crcs and usizes per member, and payloads: the
   bytes as stored. Returns the archive as a raw vector, or R_NilValue when
   it would not fit one. */
SEXP zunpy_zip_build(SEXP names, SEXP methods, SEXP crcs, SEXP usizes,
                     SEXP payloads)
{
    size_t n = (size_t)XLENGTH(names);
    znp_zip_entry *e = (znp_zip_entry *)(void *)R_alloc(n ? n : 1, sizeof(znp_zip_entry));
    for (size_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(names, (R_xlen_t)i);
        SEXP p = VECTOR_ELT(payloads, (R_xlen_t)i);
        e[i].name = CHAR(s);
        e[i].name_len = (size_t)LENGTH(s);
        e[i].method = (uint16_t)INTEGER(methods)[i];
        e[i].crc = (uint32_t)REAL(crcs)[i];
        e[i].usize = (uint64_t)REAL(usizes)[i];
        e[i].csize = (uint64_t)XLENGTH(p);
        e[i].payload = RAW(p);
    }
    uint64_t total = znp_zip_write(e, n, NULL);
    if (total > (uint64_t)R_XLEN_T_MAX)
        return R_NilValue;
    SEXP out = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t)total));
    znp_zip_write(e, n, RAW(out));
    UNPROTECT(1);
    return out;
}
