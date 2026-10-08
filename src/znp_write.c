/*
 * znp_write.c -- R values to .npy bytes (design 7, 8).
 *
 * The output is deterministic and byte-identical to numpy.save() for the
 * same array: the header dict is formatted as NumPy's
 * _write_array_header() formats it (sorted keys, repr() of each value, the
 * spare spaces after the shape that let NumPy grow an array in place), and
 * padded as its _wrap_header() pads it. Data is little-endian, through
 * zubin's pack kernels, so narrowing and range rules are zubin's.
 *
 * The result's size is known before anything is written, so it is one raw
 * vector allocated up front: R owns every byte, and an interrupt or a
 * refused value leaves nothing to free. Nothing here calls Rf_error().
 */
#include <limits.h>
#include <stdio.h>
#include <string.h>

#include <zubin.h>

#include "znp_r.h"

/* numpy/lib/format.py: ARRAY_ALIGN and GROWTH_AXIS_MAX_DIGITS. */
#define ZNP_ALIGN 64
#define ZNP_GROWTH_DIGITS 21

typedef enum {
    ZNP_WRITE_OK = 0,
    ZNP_WRITE_NA,           /* an NA the target cannot hold */
    ZNP_WRITE_RANGE,        /* a value outside the target type */
    ZNP_WRITE_INVALID,      /* a string that is not valid UTF-8 */
    ZNP_WRITE_TOO_LARGE     /* more bytes than a raw vector holds */
} znp_write_status;

static const char *write_status_name(znp_write_status st)
{
    switch (st) {
    case ZNP_WRITE_OK:        return "ZNP_OK";
    case ZNP_WRITE_NA:        return "ZNP_WRITE_NA";
    case ZNP_WRITE_RANGE:     return "ZNP_WRITE_RANGE";
    case ZNP_WRITE_INVALID:   return "ZNP_WRITE_INVALID";
    case ZNP_WRITE_TOO_LARGE: return "ZNP_WRITE_TOO_LARGE";
    }
    return "ZNP_ERR_UNKNOWN";
}

/* The dict, exactly as NumPy writes it, into buf (cap bytes, enough for
   descr plus 64 * 24 + 128); returns its length. descr is the repr() of
   NumPy's descr: a quoted string, or the list of a structured dtype. */
static size_t format_dict(char *buf, size_t cap, const char *descr,
                          int fortran, const uint64_t *shape, int k)
{
    size_t n = 0;
    n += (size_t)snprintf(buf + n, cap - n, "{'descr': %s, 'fortran_order': %s, 'shape': (",
                          descr, fortran ? "True" : "False");
    for (int j = 0; j < k; j++)
        n += (size_t)snprintf(buf + n, cap - n, j ? ", %llu" : "%llu",
                              (unsigned long long)shape[j]);
    n += (size_t)snprintf(buf + n, cap - n, "%s), }", k == 1 ? "," : "");
    if (k > 0) {
        char digits[24];
        int len = snprintf(digits, sizeof digits, "%llu",
                           (unsigned long long)shape[fortran ? k - 1 : 0]);
        for (int s = len; s < ZNP_GROWTH_DIGITS; s++)
            buf[n++] = ' ';
    }
    return n;
}

/* The whole file around a dict: magic, version, length, the dict, padding
   as _wrap_header() pads it, and room for data_bytes of data, which the
   caller fills from *data. The version is 1.0 while the length fits two
   bytes, else 2.0, and 3.0 when the dict needs UTF-8 (a field name with no
   Latin-1 form). dict is UTF-8; versions 1 and 2 store it as Latin-1.
   Returns R_NilValue when the file would not fit a raw vector. */
static SEXP npy_frame(const char *dict, size_t dlen, int need_utf8,
                      size_t data_bytes, uint8_t **data)
{
    /* Latin-1 bytes of the dict, for versions 1 and 2. */
    char *text = (char *)dict;
    size_t tlen = dlen;
    if (!need_utf8) {
        text = R_alloc(dlen ? dlen : 1, 1);
        tlen = 0;
        for (size_t i = 0; i < dlen; i++) {
            unsigned char c = (unsigned char)dict[i];
            if (c >= 0xC0 && i + 1 < dlen) {      /* U+0080..U+00FF: two bytes */
                text[tlen++] = (char)(((c & 0x1F) << 6) | ((unsigned char)dict[i + 1] & 0x3F));
                i++;
            } else
                text[tlen++] = (char)c;
        }
    }
    size_t hlen = tlen + 1, prefix = need_utf8 ? 12 : 10;
    size_t pad = ZNP_ALIGN - ((prefix + hlen) % ZNP_ALIGN);
    int major = need_utf8 ? 3 : 1;
    if (!need_utf8 && hlen + pad > 65535) {
        major = 2;
        prefix = 12;
        pad = ZNP_ALIGN - ((prefix + hlen) % ZNP_ALIGN);
    }
    size_t head = prefix + hlen + pad;
    if (data_bytes > (size_t)R_XLEN_T_MAX - head)
        return R_NilValue;
    SEXP raw = Rf_allocVector(RAWSXP, (R_xlen_t)(head + data_bytes));
    uint8_t *p = RAW(raw);
    static const uint8_t magic[6] = {0x93, 'N', 'U', 'M', 'P', 'Y'};
    memcpy(p, magic, 6);
    p[6] = (uint8_t)major;
    p[7] = 0;
    if (major == 1)
        zb_wr_u16le(p + 8, (uint16_t)(hlen + pad));
    else
        zb_wr_u32le(p + 8, (uint32_t)(hlen + pad));
    memcpy(p + prefix, text, tlen);
    memset(p + prefix + tlen, ' ', pad);
    p[head - 1] = '\n';
    *data = p + head;
    return raw;
}

typedef struct {
    char kind;          /* b i u f c, S U, M m */
    int  width;         /* bytes; for U and S the character width, -1 for the widest value */
    char unit[4];       /* M and m */
    int64_t scale;      /* M and m from doubles: ticks per R unit */
    int  na_allow;
    int  is_int64;      /* x is bit64's integer64 */
} znp_target;

static zb_field target_field(const znp_target *t)
{
    zb_field f;
    memset(&f, 0, sizeof f);
    f.count = 1;
    f.size = (uint32_t)t->width;
    switch (t->kind) {
    case 'b': f.type = ZB_BOOL; break;
    case 'i': f.type = t->width == 1 ? ZB_I8 : t->width == 2 ? ZB_I16
                     : t->width == 4 ? ZB_I32 : ZB_I64; break;
    case 'u': f.type = t->width == 1 ? ZB_U8 : t->width == 2 ? ZB_U16
                     : t->width == 4 ? ZB_U32 : ZB_U64; break;
    case 'f': f.type = t->width == 2 ? ZB_F16 : t->width == 4 ? ZB_F32 : ZB_F64; break;
    default:  f.type = t->width == 8 ? ZB_F32 : ZB_F64; break;  /* complex parts */
    }
    return f;
}

/* Packs x, in R's order, into dst, one element every `stride` bytes.
   *replaced counts logical NAs written as False under na = "allow". */
static zb_status pack(SEXP x, const znp_target *t, uint8_t *dst, size_t stride,
                      size_t *bad, R_xlen_t *replaced)
{
    size_t n = (size_t)XLENGTH(x), w = stride;
    zb_field f = target_field(t);
    *replaced = 0;
    if (t->kind == 'U' || t->kind == 'S') {
        int st = znp_write_text(x, dst, stride, (size_t)t->width, t->kind == 'U', bad);
        return st == 0 ? ZB_OK : st == 1 ? ZB_ERR_RANGE : ZB_ERR_INVALID;
    }
    if (t->kind == 'M' || t->kind == 'm') {
        if (t->is_int64) {
            /* Counts as they are; NA_integer64_ is NaT. */
            f.type = ZB_I64;
            f.size = 8;
            return zb_pack_i64(dst, n, stride, &f, (const int64_t *)(const void *)REAL(x), 1, bad);
        }
        return znp_write_counts(REAL(x), n, t->scale, dst, stride, bad) ? ZB_ERR_RANGE : ZB_OK;
    }
    /* R's own bytes are the file's for f8, i4 and c16, contiguous, on a
       little-endian host (design 16); an i4 holding NA goes the long way,
       which refuses it or writes it as na says. */
    if (znp_fast_path() && stride == (size_t)t->width && !t->is_int64 &&
        ((TYPEOF(x) == REALSXP && t->kind == 'f' && t->width == 8) ||
         (TYPEOF(x) == CPLXSXP && t->kind == 'c' && t->width == 16) ||
         (TYPEOF(x) == INTSXP && t->kind == 'i' && t->width == 4))) {
        int clean = !(TYPEOF(x) == INTSXP && !t->na_allow && znp_has_na(INTEGER(x), n));
        if (clean) {
            if (n)
                memcpy(dst, znp_dataptr(x), n * stride);
            return ZB_OK;
        }
    }
    switch (TYPEOF(x)) {
    case RAWSXP:
        for (size_t i = 0; i < n; i++)
            dst[i * stride] = RAW(x)[i];
        return ZB_OK;
    case CPLXSXP: {
        const Rcomplex *s = COMPLEX(x);
        size_t half = (size_t)t->width / 2;
        for (size_t i = 0; i < n; i++) {
            uint8_t *p = dst + i * w;
            if (f.type == ZB_F32) {
                zb_wr_f32le(p, zb_int_f64_to_f32(s[i].r));
                zb_wr_f32le(p + half, zb_int_f64_to_f32(s[i].i));
            } else {
                zb_wr_f64le(p, s[i].r);
                zb_wr_f64le(p + half, s[i].i);
            }
        }
        return ZB_OK;
    }
    case LGLSXP:
    case INTSXP: {
        const int *s = TYPEOF(x) == LGLSXP ? LOGICAL(x) : INTEGER(x);
        if (f.type == ZB_I32 || f.type == ZB_I16 || f.type == ZB_I8 ||
            f.type == ZB_U16 || f.type == ZB_U8 || f.type == ZB_BOOL) {
            if (TYPEOF(x) == LGLSXP && t->na_allow) {
                /* NumPy has no missing boolean: NA becomes False (design 7.1). */
                int *c = (int *)(void *)R_alloc(n ? n : 1, sizeof(int));
                for (size_t i = 0; i < n; i++) {
                    c[i] = s[i] == NA_LOGICAL ? 0 : s[i];
                    *replaced += s[i] == NA_LOGICAL;
                }
                s = c;
            }
            return zb_pack_i32(dst, n, w, &f, s, t->na_allow, bad);
        }
        /* Into a float or a 64-bit integer: through double, NA as NA_real_. */
        double *d = (double *)(void *)R_alloc(n ? n : 1, sizeof(double));
        for (size_t i = 0; i < n; i++) {
            if (s[i] == NA_INTEGER && !t->na_allow) {
                *bad = i;
                return ZB_ERR_NA;
            }
            d[i] = s[i] == NA_INTEGER ? NA_REAL : (double)s[i];
        }
        return zb_pack_f64(dst, n, w, &f, d, t->na_allow, bad);
    }
    default: /* REALSXP */
        if (t->is_int64)
            return zb_pack_i64(dst, n, w, &f, (const int64_t *)(const void *)REAL(x),
                               t->na_allow, bad);
        return zb_pack_f64(dst, n, w, &f, REAL(x), t->na_allow, bad);
    }
}

/* The dtype string of a target, as NumPy writes it. */
static void format_descr(const znp_target *t, char *buf, size_t cap)
{
    if (t->kind == 'U')
        snprintf(buf, cap, "'<U%d'", t->width);
    else if (t->kind == 'S')
        snprintf(buf, cap, "'|S%d'", t->width);
    else if (t->kind == 'M' || t->kind == 'm')
        snprintf(buf, cap, "'<%c8[%s]'", t->kind, t->unit);
    else
        snprintf(buf, cap, "'%c%c%d'", t->width == 1 && t->kind != 'c' ? '|' : '<',
                 t->kind, t->width);
}

/* Bytes per element of a target. */
static size_t item_width(const znp_target *t)
{
    if (t->kind == 'U')
        return 4 * (size_t)t->width;
    if (t->kind == 'M' || t->kind == 'm')
        return 8;
    return (size_t)t->width;
}

static SEXP result_list(void)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 5));
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, 5));
    const char *names[] = {"status", "index", "value", "replaced", "column"};
    for (int i = 0; i < 5; i++)
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nm);
    UNPROTECT(2);
    return out;
}

/* A refused value: status, its 1-based index, and the 1-based column. */
static void set_fault(SEXP out, zb_status st, size_t bad, int column)
{
    znp_write_status ws = st == ZB_ERR_NA ? ZNP_WRITE_NA
                        : st == ZB_ERR_INVALID ? ZNP_WRITE_INVALID : ZNP_WRITE_RANGE;
    SET_VECTOR_ELT(out, 0, Rf_mkString(write_status_name(ws)));
    SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)bad + 1));
    SET_VECTOR_ELT(out, 4, Rf_ScalarInteger(column >= 0 ? column + 1 : NA_INTEGER));
}

/* spec: list(kind, width, unit, scale); shape: R's dims as doubles (the
   logical shape); opts: c(order_c, na_allow, is_int64). Returns
   list(status, index, value, replaced). */
SEXP zunpy_encode(SEXP x, SEXP spec, SEXP shape_r, SEXP opts)
{
    znp_target t;
    memset(&t, 0, sizeof t);
    t.kind = CHAR(STRING_ELT(VECTOR_ELT(spec, 0), 0))[0];
    t.width = INTEGER(VECTOR_ELT(spec, 1))[0];
    snprintf(t.unit, sizeof t.unit, "%s", CHAR(STRING_ELT(VECTOR_ELT(spec, 2), 0)));
    t.scale = (int64_t)REAL(VECTOR_ELT(spec, 3))[0];
    int order_c = INTEGER(opts)[0];
    t.na_allow = INTEGER(opts)[1];
    t.is_int64 = INTEGER(opts)[2];

    int k = (int)XLENGTH(shape_r);
    uint64_t shape[ZNP_MAX_DIMS_CAP];
    int nontrivial = 0;
    for (int j = 0; j < k; j++) {
        shape[j] = (uint64_t)REAL(shape_r)[j];
        nontrivial += shape[j] > 1;
    }
    size_t n = (size_t)XLENGTH(x);

    /* NumPy's own rule: an array both C- and Fortran-contiguous (empty, or
       with at most one dimension above 1) is written as C order, and so has
       the same bytes either way. */
    int layout_matters = k >= 2 && n > 0 && nontrivial >= 2;
    int fortran = layout_matters && !order_c;
    int permute = layout_matters && order_c;

    /* The width of a string dtype: given, or the widest value, at least 1
       as NumPy makes it. */
    if ((t.kind == 'U' || t.kind == 'S') && t.width < 0) {
        size_t wid = znp_text_width(x, t.kind == 'U');
        if (wid > (size_t)INT_MAX / 4)
            wid = (size_t)INT_MAX / 4;
        t.width = wid > 0 ? (int)wid : 1;
    }
    char descr[40];
    format_descr(&t, descr, sizeof descr);
    char dict[ZNP_MAX_DIMS_CAP * 24 + 256];
    size_t dlen = format_dict(dict, sizeof dict, descr, fortran, shape, k);

    SEXP out = PROTECT(result_list());
    size_t w = item_width(&t);
    uint8_t *data;
    SEXP raw = (w > 0 && n > (size_t)R_XLEN_T_MAX / w) ? R_NilValue
             : npy_frame(dict, dlen, 0, n * w, &data);
    if (raw == R_NilValue) {
        SET_VECTOR_ELT(out, 0, Rf_mkString(write_status_name(ZNP_WRITE_TOO_LARGE)));
        UNPROTECT(1);
        return out;
    }
    PROTECT(raw);
    uint8_t *into = permute ? (uint8_t *)(void *)R_alloc(n, w) : data;
    size_t bad = 0;
    R_xlen_t replaced = 0;
    zb_status st = pack(x, &t, into, w, &bad, &replaced);
    if (st != ZB_OK) {
        set_fault(out, st, bad, -1);
        UNPROTECT(2);
        return out;
    }
    if (permute)
        znp_permute(into, data, w, n, shape, k, 0);

    SET_VECTOR_ELT(out, 0, Rf_mkString(write_status_name(ZNP_WRITE_OK)));
    SET_VECTOR_ELT(out, 2, raw);
    SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)replaced));
    UNPROTECT(2);
    return out;
}

/* Python's repr() of a field name, appended to buf: single quotes unless
   the name holds ' and no ", backslash escapes for the quote, backslash,
   tab, newline and carriage return, \xhh for other control characters and
   for U+007F..U+00A0 and U+00AD, and every other character as it is. For
   names with unusual non-printing characters past U+00FF, NumPy's own
   escapes may differ (design 7.3). Returns the new length; *non_latin1 is
   set when a character is past U+00FF. */
static size_t repr_name(char *buf, size_t n, const char *s, size_t len, int *non_latin1)
{
    char q = (memchr(s, '\'', len) && !memchr(s, '"', len)) ? '"' : '\'';
    buf[n++] = q;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        uint32_t cp = c;
        size_t extra = 0;
        if (c >= 0xF0) { cp = c & 0x07; extra = 3; }
        else if (c >= 0xE0) { cp = c & 0x0F; extra = 2; }
        else if (c >= 0xC0) { cp = c & 0x1F; extra = 1; }
        for (size_t k = 1; k <= extra && i + k < len; k++)
            cp = (cp << 6) | ((unsigned char)s[i + k] & 0x3F);
        if (cp > 0xFF)
            *non_latin1 = 1;
        if (cp == (uint32_t)q || cp == '\\') {
            buf[n++] = '\\';
            buf[n++] = (char)cp;
        } else if (cp == '\t' || cp == '\n' || cp == '\r') {
            buf[n++] = '\\';
            buf[n++] = cp == '\t' ? 't' : cp == '\n' ? 'n' : 'r';
        } else if (cp < 0x20 || (cp >= 0x7F && cp <= 0xA0) || cp == 0xAD) {
            n += (size_t)snprintf(buf + n, 5, "\\x%02x", (unsigned)cp);
        } else {
            memcpy(buf + n, s + i, extra + 1);
            n += extra + 1;
        }
        i += extra;
    }
    buf[n++] = q;
    return n;
}

/* A data frame as a structured array (design 7.3): one field per column,
   packed, in column order. cols are bare vectors; specs as for
   zunpy_encode(); names are the column names in UTF-8; shape is the
   array's shape in R's order (nrow, or npy_shape); opts: c(order_c,
   na_allow), and is_int64 per column in int64s. Returns list(status,
   index, value, replaced, column). */
SEXP zunpy_encode_records(SEXP cols, SEXP specs, SEXP names, SEXP shape_r,
                          SEXP opts, SEXP int64s)
{
    int ncol = (int)XLENGTH(cols);
    int order_c = INTEGER(opts)[0];
    znp_target *t = (znp_target *)(void *)R_alloc(ncol ? (size_t)ncol : 1, sizeof(znp_target));
    size_t *off = (size_t *)(void *)R_alloc(ncol ? (size_t)ncol : 1, sizeof(size_t));
    size_t rs = 0, need = 64;
    for (int c = 0; c < ncol; c++) {
        SEXP spec = VECTOR_ELT(specs, c);
        memset(&t[c], 0, sizeof t[c]);
        t[c].kind = CHAR(STRING_ELT(VECTOR_ELT(spec, 0), 0))[0];
        t[c].width = INTEGER(VECTOR_ELT(spec, 1))[0];
        snprintf(t[c].unit, sizeof t[c].unit, "%s", CHAR(STRING_ELT(VECTOR_ELT(spec, 2), 0)));
        t[c].scale = (int64_t)REAL(VECTOR_ELT(spec, 3))[0];
        t[c].na_allow = INTEGER(opts)[1];
        t[c].is_int64 = LOGICAL(int64s)[c];
        if ((t[c].kind == 'U' || t[c].kind == 'S') && t[c].width < 0) {
            size_t wid = znp_text_width(VECTOR_ELT(cols, c), t[c].kind == 'U');
            if (wid > (size_t)INT_MAX / 4)
                wid = (size_t)INT_MAX / 4;
            t[c].width = wid > 0 ? (int)wid : 1;
        }
        off[c] = rs;
        rs += item_width(&t[c]);
        /* repr() of a name: at most 4 bytes per byte, quotes, the descr */
        need += 4 * (size_t)LENGTH(STRING_ELT(names, c)) + 64;
    }

    int k = (int)XLENGTH(shape_r);
    uint64_t shape[ZNP_MAX_DIMS_CAP];
    int nontrivial = 0;
    size_t n = 1;
    for (int j = 0; j < k; j++) {
        shape[j] = (uint64_t)REAL(shape_r)[j];
        nontrivial += shape[j] > 1;
        n *= (size_t)shape[j];
    }
    int layout_matters = k >= 2 && n > 0 && nontrivial >= 2;
    int fortran = layout_matters && !order_c;
    int permute = layout_matters && order_c;

    /* [('a', '<i4'), ('b', '<f8')], as repr(dtype.descr) */
    char *descr = R_alloc(need, 1);
    size_t dn = 0;
    int non_latin1 = 0;
    descr[dn++] = '[';
    for (int c = 0; c < ncol; c++) {
        SEXP nm = STRING_ELT(names, c);
        if (c) {
            descr[dn++] = ',';
            descr[dn++] = ' ';
        }
        descr[dn++] = '(';
        dn = repr_name(descr, dn, CHAR(nm), (size_t)LENGTH(nm), &non_latin1);
        char d[40];
        format_descr(&t[c], d, sizeof d);
        dn += (size_t)snprintf(descr + dn, need - dn, ", %s)", d);
    }
    descr[dn++] = ']';
    descr[dn] = '\0';

    size_t cap = dn + ZNP_MAX_DIMS_CAP * 24 + 256;
    char *dict = R_alloc(cap, 1);
    size_t dlen = format_dict(dict, cap, descr, fortran, shape, k);

    SEXP out = PROTECT(result_list());
    uint8_t *data;
    SEXP raw = (rs > 0 && n > (size_t)R_XLEN_T_MAX / rs) ? R_NilValue
             : npy_frame(dict, dlen, non_latin1, n * rs, &data);
    if (raw == R_NilValue) {
        SET_VECTOR_ELT(out, 0, Rf_mkString(write_status_name(ZNP_WRITE_TOO_LARGE)));
        UNPROTECT(1);
        return out;
    }
    PROTECT(raw);
    uint8_t *into = permute ? (uint8_t *)(void *)R_alloc(n, rs) : data;
    R_xlen_t replaced = 0;
    for (int c = 0; c < ncol; c++) {
        size_t bad = 0;
        R_xlen_t rep = 0;
        zb_status st = pack(VECTOR_ELT(cols, c), &t[c], into + off[c], rs, &bad, &rep);
        if (st != ZB_OK) {
            set_fault(out, st, bad, c);
            UNPROTECT(2);
            return out;
        }
        replaced += rep;
    }
    if (permute)
        znp_permute(into, data, rs, n, shape, k, 0);

    SET_VECTOR_ELT(out, 0, Rf_mkString(write_status_name(ZNP_WRITE_OK)));
    SET_VECTOR_ELT(out, 2, raw);
    SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)replaced));
    UNPROTECT(2);
    return out;
}
