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
    ZNP_WRITE_TOO_LARGE     /* more bytes than a raw vector holds */
} znp_write_status;

static const char *write_status_name(znp_write_status st)
{
    switch (st) {
    case ZNP_WRITE_OK:        return "ZNP_OK";
    case ZNP_WRITE_NA:        return "ZNP_WRITE_NA";
    case ZNP_WRITE_RANGE:     return "ZNP_WRITE_RANGE";
    case ZNP_WRITE_TOO_LARGE: return "ZNP_WRITE_TOO_LARGE";
    }
    return "ZNP_ERR_UNKNOWN";
}

/* The dict, exactly as NumPy writes it, into buf; returns its length. */
static size_t format_dict(char *buf, size_t cap, const char *descr,
                          int fortran, const uint64_t *shape, int k)
{
    size_t n = 0;
    n += (size_t)snprintf(buf + n, cap - n, "{'descr': '%s', 'fortran_order': %s, 'shape': (",
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

typedef struct {
    char kind;          /* b i u f c */
    int  width;         /* bytes */
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

/* Packs x, in R's order, into dst at `width` bytes an element. *replaced
   counts logical NAs written as False under na = "allow". */
static zb_status pack(SEXP x, const znp_target *t, uint8_t *dst, size_t *bad,
                      R_xlen_t *replaced)
{
    size_t n = (size_t)XLENGTH(x), w = (size_t)t->width;
    zb_field f = target_field(t);
    *replaced = 0;
    switch (TYPEOF(x)) {
    case RAWSXP:
        if (n)
            memcpy(dst, RAW(x), n);
        return ZB_OK;
    case CPLXSXP: {
        const Rcomplex *s = COMPLEX(x);
        size_t half = w / 2;
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

/* spec: list(kind, width); shape: R's dims as doubles (the logical shape);
   opts: c(order_c, na_allow, is_int64). Returns list(status, index, value,
   replaced). */
SEXP zunpy_encode(SEXP x, SEXP spec, SEXP shape_r, SEXP opts)
{
    znp_target t;
    t.kind = CHAR(STRING_ELT(VECTOR_ELT(spec, 0), 0))[0];
    t.width = INTEGER(VECTOR_ELT(spec, 1))[0];
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

    char descr[16];
    int one_byte = t.width == 1 && t.kind != 'c';
    snprintf(descr, sizeof descr, "%c%c%d", one_byte ? '|' : '<', t.kind, t.width);

    char dict[ZNP_MAX_DIMS_CAP * 24 + 256];
    size_t dlen = format_dict(dict, sizeof dict, descr, fortran, shape, k);

    /* _wrap_header(): version 1.0 while the length fits two bytes. */
    size_t hlen = dlen + 1, prefix = 10;
    size_t pad = ZNP_ALIGN - ((prefix + hlen) % ZNP_ALIGN);
    int major = 1;
    if (hlen + pad > 65535) {
        major = 2;
        prefix = 12;
        pad = ZNP_ALIGN - ((prefix + hlen) % ZNP_ALIGN);
    }
    size_t head = prefix + hlen + pad;

    SEXP out = PROTECT(Rf_allocVector(VECSXP, 4));
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, 4));
    const char *names[] = {"status", "index", "value", "replaced"};
    for (int i = 0; i < 4; i++)
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nm);

    size_t w = (size_t)t.width;
    if (n > ((size_t)R_XLEN_T_MAX - head) / w) {
        SET_VECTOR_ELT(out, 0, Rf_mkString(write_status_name(ZNP_WRITE_TOO_LARGE)));
        UNPROTECT(2);
        return out;
    }
    SEXP raw = PROTECT(Rf_allocVector(RAWSXP, (R_xlen_t)(head + n * w)));
    uint8_t *p = RAW(raw);
    static const uint8_t magic[6] = {0x93, 'N', 'U', 'M', 'P', 'Y'};
    memcpy(p, magic, 6);
    p[6] = (uint8_t)major;
    p[7] = 0;
    if (major == 1)
        zb_wr_u16le(p + 8, (uint16_t)(hlen + pad));
    else
        zb_wr_u32le(p + 8, (uint32_t)(hlen + pad));
    memcpy(p + prefix, dict, dlen);
    memset(p + prefix + dlen, ' ', pad);
    p[head - 1] = '\n';

    uint8_t *data = p + head;
    uint8_t *into = permute ? (uint8_t *)(void *)R_alloc(n, w) : data;
    size_t bad = 0;
    R_xlen_t replaced = 0;
    zb_status st = pack(x, &t, into, &bad, &replaced);
    if (st != ZB_OK) {
        znp_write_status ws = st == ZB_ERR_NA ? ZNP_WRITE_NA : ZNP_WRITE_RANGE;
        SET_VECTOR_ELT(out, 0, Rf_mkString(write_status_name(ws)));
        SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)bad + 1));
        UNPROTECT(3);
        return out;
    }
    if (permute)
        znp_permute(into, data, w, n, shape, k, 0);

    SET_VECTOR_ELT(out, 0, Rf_mkString(write_status_name(ZNP_WRITE_OK)));
    SET_VECTOR_ELT(out, 2, raw);
    SET_VECTOR_ELT(out, 3, Rf_ScalarReal((double)replaced));
    UNPROTECT(3);
    return out;
}
