/*
 * znp_build.c -- the build phase (design 4, 6): a checked plan to an R
 * value.
 *
 * Everything allocated here is sized from the plan, whose sizes the check
 * phase has compared with the bytes present (design 12). Values go through
 * zubin's unpack kernels (zubin/layout.h), so the byte order and the
 * exactness rules are zubin's: an i4 of -2^31 is refused unless NA is
 * allowed, and a 64-bit integer that a double cannot hold exactly is
 * refused rather than rounded.
 *
 * Nothing here calls Rf_error(): a refusal comes back as a status name, an
 * element index and a byte offset, and R/decode.R raises it.
 */
#include <limits.h>
#include <string.h>

#include <zubin.h>

#include "znp_check.h"
#include "znp_r.h"

/* Elements converted between interrupt checks. */
#define ZNP_CHUNK ((size_t)1 << 20)

typedef enum {
    ZNP_BUILD_OK = 0,
    ZNP_BUILD_NA,               /* an NA with no place in the target */
    ZNP_BUILD_UNREPRESENTABLE,  /* a value or a dimension R cannot hold */
    ZNP_BUILD_INVALID,          /* a string that is not valid in its encoding */
    ZNP_BUILD_NOT_YET           /* unused since Stage 5; kept for the status table */
} znp_build_status;

static const char *build_status_name(znp_build_status st)
{
    switch (st) {
    case ZNP_BUILD_OK:              return "ZNP_OK";
    case ZNP_BUILD_NA:              return "ZNP_BUILD_NA";
    case ZNP_BUILD_UNREPRESENTABLE: return "ZNP_BUILD_UNREPRESENTABLE";
    case ZNP_BUILD_INVALID:         return "ZNP_BUILD_INVALID";
    case ZNP_BUILD_NOT_YET:         return "ZNP_BUILD_NOT_YET";
    }
    return "ZNP_ERR_UNKNOWN";
}

typedef struct {
    int order_file;     /* order = "file": no permutation */
    int as_integer64;   /* int64 = "integer64" */
    int na_allow;       /* na = "allow" */
    int strings_raw;    /* strings = "raw": S<n> as a list of raw */
    int encoding;       /* of S<n>: 0 UTF-8, 1 Latin-1, 2 bytes */
    int datetime_raw;   /* datetime = "integer64" */
} znp_opts;

typedef struct {
    znp_build_status status;
    size_t           index;     /* 0-based element, in file order */
    int              dim;       /* for a dimension fault, which one */
} znp_build_fault;

/* The zubin field type for a scalar dtype, and the R vector type it fills. */
static int field_for(const znp_dtype *dt, const znp_opts *o, zb_field *f,
                     SEXPTYPE *rtype)
{
    memset(f, 0, sizeof *f);
    f->count = 1;
    f->size = (uint32_t)dt->itemsize;
    f->big_endian = dt->order == '>';
    switch (dt->kind) {
    case 'b': f->type = ZB_BOOL; *rtype = LGLSXP; break;
    case 'i':
        switch (dt->itemsize) {
        case 1: f->type = ZB_I8; *rtype = INTSXP; break;
        case 2: f->type = ZB_I16; *rtype = INTSXP; break;
        case 4: f->type = ZB_I32; *rtype = INTSXP; break;
        default: f->type = ZB_I64; *rtype = REALSXP; break;
        }
        break;
    case 'u':
        switch (dt->itemsize) {
        case 1: f->type = ZB_U8; *rtype = INTSXP; break;
        case 2: f->type = ZB_U16; *rtype = INTSXP; break;
        case 4: f->type = ZB_U32; *rtype = REALSXP; break;
        default: f->type = ZB_U64; *rtype = REALSXP; break;
        }
        break;
    case 'f':
        f->type = dt->itemsize == 2 ? ZB_F16 : dt->itemsize == 4 ? ZB_F32 : ZB_F64;
        *rtype = REALSXP;
        break;
    case 'c':
        /* Two floats, read element by element below. */
        f->type = dt->itemsize == 8 ? ZB_F32 : ZB_F64;
        *rtype = CPLXSXP;
        break;
    default:
        return 0;
    }
    (void)o;
    return 1;
}

/* n numeric, boolean or complex elements `stride` bytes apart, from
   element `first`, into the matching slots of out. */
static zb_status convert(const uint8_t *base0, size_t first, size_t n,
                         size_t stride, const zb_field *f, const znp_opts *o,
                         SEXP out, size_t *bad)
{
    const uint8_t *base = base0 + first * stride;
    switch (TYPEOF(out)) {
    case LGLSXP:
        return zb_unpack_i32(base, n, stride, f, LOGICAL(out) + first, 1, bad);
    case INTSXP:
        return zb_unpack_i32(base, n, stride, f, INTEGER(out) + first, o->na_allow, bad);
    case CPLXSXP: {
        Rcomplex *d = COMPLEX(out) + first;
        size_t half = f->size / 2;
        int be = f->big_endian;
        for (size_t i = 0; i < n; i++) {
            const uint8_t *p = base + i * stride;
            if (f->type == ZB_F32) {
                d[i].r = be ? zb_rd_f32be(p) : zb_rd_f32le(p);
                d[i].i = be ? zb_rd_f32be(p + half) : zb_rd_f32le(p + half);
            } else {
                d[i].r = be ? zb_rd_f64be(p) : zb_rd_f64le(p);
                d[i].i = be ? zb_rd_f64be(p + half) : zb_rd_f64le(p + half);
            }
        }
        return ZB_OK;
    }
    default: /* REALSXP */
        if (f->type == ZB_I64 || f->type == ZB_U64) {
            double *d = REAL(out) + first;
            if (!o->as_integer64)
                return zb_unpack_f64x(base, n, stride, f, d, bad);
            /* integer64 is the int64 bit pattern in a double. */
            int64_t *v = (int64_t *)(void *)d;
            zb_status st = zb_unpack_i64(base, n, stride, f, v, bad);
            if (st == ZB_OK && !o->na_allow) {
                /* -2^63 is bit64's NA_integer64_. */
                for (size_t i = 0; i < n; i++)
                    if (v[i] == INT64_MIN) {
                        *bad = i;
                        return ZB_ERR_NA;
                    }
            }
            return st;
        }
        return zb_unpack_f64(base, n, stride, f, REAL(out) + first);
    }
}

/* One column: n elements of dtype dt, `stride` bytes apart from base, as an
   R vector (a list for S with strings = "raw" and for V). On a refusal,
   fault is set and the return is R_NilValue. */
static SEXP read_column(const uint8_t *base, size_t n, size_t stride,
                        const znp_dtype *dt, const znp_opts *o,
                        znp_build_fault *fault)
{
    zb_field f;
    SEXPTYPE rtype;
    size_t bad = 0;
    int status = 0;
    SEXP out;

    if (field_for(dt, o, &f, &rtype)) {
        out = PROTECT(Rf_allocVector(rtype, (R_xlen_t)n));
        for (size_t first = 0; first < n; first += ZNP_CHUNK) {
            size_t m = n - first < ZNP_CHUNK ? n - first : ZNP_CHUNK;
            zb_status st = convert(base, first, m, stride, &f, o, out, &bad);
            if (st != ZB_OK) {
                fault->status = st == ZB_ERR_RANGE && rtype == INTSXP ? ZNP_BUILD_NA
                              : st == ZB_ERR_NA ? ZNP_BUILD_NA
                              : ZNP_BUILD_UNREPRESENTABLE;
                fault->index = first + bad;
                UNPROTECT(1);
                return R_NilValue;
            }
            R_CheckUserInterrupt();
        }
        UNPROTECT(1);
        return out;
    }

    switch (dt->kind) {
    case 'S':
        if (o->strings_raw)
            return znp_read_bytes(base, n, stride, (size_t)dt->itemsize, 1);
        out = znp_read_s(base, n, stride, (size_t)dt->itemsize, o->encoding, &status, &bad);
        break;
    case 'U':
        out = znp_read_u(base, n, stride, (size_t)dt->chars, dt->order == '>', &status, &bad);
        break;
    case 'V':
        return znp_read_bytes(base, n, stride, (size_t)dt->itemsize, 0);
    default: { /* M, m */
        int64_t scale = o->datetime_raw ? 0 : znp_time_scale(dt->kind, dt->unit);
        out = PROTECT(Rf_allocVector(REALSXP, (R_xlen_t)n));
        if (scale == 0) {
            /* integer64: the counts as they are; NaT is NA_integer64_. */
            memset(&f, 0, sizeof f);
            f.type = ZB_I64;
            f.count = 1;
            f.size = 8;
            f.big_endian = dt->order == '>';
            zb_unpack_i64(base, n, stride, &f, (int64_t *)(void *)REAL(out), &bad);
        } else if (znp_read_counts(base, n, stride, dt->order == '>', scale, REAL(out), &bad))
            status = 4;
        UNPROTECT(1);
        break;
    }
    }
    if (status != 0) {
        fault->status = status == 2 ? ZNP_BUILD_INVALID : ZNP_BUILD_UNREPRESENTABLE;
        fault->index = bad;
        return R_NilValue;
    }
    return out;
}

/* A C-order vector of strings or a list into R's order: the permutation is
   computed on indices, and elements are moved with the write barrier. */
static SEXP permute_elements(SEXP src, const uint64_t *shape, int k)
{
    size_t n = (size_t)XLENGTH(src);
    size_t *from = (size_t *)(void *)R_alloc(n ? n : 1, sizeof(size_t));
    size_t *to = (size_t *)(void *)R_alloc(n ? n : 1, sizeof(size_t));
    for (size_t i = 0; i < n; i++)
        from[i] = i;
    znp_permute(from, to, sizeof(size_t), n, shape, k, 1);
    SEXP dst = PROTECT(Rf_allocVector(TYPEOF(src), (R_xlen_t)n));
    for (size_t t = 0; t < n; t++) {
        if (TYPEOF(src) == STRSXP)
            SET_STRING_ELT(dst, (R_xlen_t)t, STRING_ELT(src, (R_xlen_t)to[t]));
        else
            SET_VECTOR_ELT(dst, (R_xlen_t)t, VECTOR_ELT(src, (R_xlen_t)to[t]));
    }
    UNPROTECT(1);
    return dst;
}

static SEXP dim_attr(const uint64_t *shape, int k, int reverse)
{
    SEXP dim = PROTECT(Rf_allocVector(INTSXP, k));
    for (int j = 0; j < k; j++)
        INTEGER(dim)[j] = (int)shape[reverse ? k - 1 - j : j];
    UNPROTECT(1);
    return dim;
}

/* The bare vectors and their descr strings, one per column, and the column
   names: list(columns, names, descrs). A field with a subarray of m
   elements gives m columns, name.1 to name.m, in C order (design 6.3);
   padding gives none. */
static SEXP build_records(const uint8_t *body, const znp_plan *plan,
                          const znp_opts *o, znp_build_fault *fault)
{
    size_t n = (size_t)plan->count, rs = (size_t)plan->itemsize;
    if (n > INT_MAX) {
        /* A data frame's rows are an integer. */
        fault->status = ZNP_BUILD_UNREPRESENTABLE;
        fault->dim = 0;
        return R_NilValue;
    }
    /* Rows in R's order: a C-order array of records with two or more
       dimensions is permuted record by record into one temporary first. */
    if (plan->ndim >= 2 && !plan->fortran_order && !o->order_file && n > 0) {
        uint8_t *tmp = (uint8_t *)(void *)R_alloc(n, rs ? rs : 1);
        znp_permute(body, tmp, rs, n, plan->shape, plan->ndim, 1);
        body = tmp;
    }

    size_t ncol = 0;
    for (int i = 0; i < plan->n_fields; i++) {
        uint64_t m = 1;
        for (int d = 0; d < plan->fields[i].ndim; d++)
            m *= plan->fields[i].shape[d];
        ncol += (size_t)m;
    }
    if (ncol > INT_MAX) {
        fault->status = ZNP_BUILD_UNREPRESENTABLE;
        fault->dim = 0;
        return R_NilValue;
    }
    SEXP cols = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t)ncol));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)ncol));
    SEXP descrs = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)ncol));
    size_t c = 0;
    for (int i = 0; i < plan->n_fields; i++) {
        const znp_field *f = &plan->fields[i];
        uint64_t m = 1;
        for (int d = 0; d < f->ndim; d++)
            m *= f->shape[d];
        SEXP descr = PROTECT(znp_dtype_sexp(&f->dtype));
        for (uint64_t e = 0; e < m; e++, c++) {
            const uint8_t *base = body + f->offset + e * f->dtype.itemsize;
            SEXP col = read_column(base, n, rs, &f->dtype, o, fault);
            if (fault->status != ZNP_BUILD_OK) {
                fault->dim = -1;
                UNPROTECT(4);
                return R_NilValue;
            }
            SET_VECTOR_ELT(cols, (R_xlen_t)c, col);
            SET_STRING_ELT(descrs, (R_xlen_t)c, STRING_ELT(descr, 0));
            if (f->ndim == 0)
                SET_STRING_ELT(names, (R_xlen_t)c,
                               Rf_mkCharLenCE(f->name, (int)f->name_len, CE_UTF8));
            else {
                char *buf = R_alloc(f->name_len + 24, 1);
                memcpy(buf, f->name, f->name_len);
                int k = snprintf(buf + f->name_len, 24, ".%llu", (unsigned long long)e + 1);
                SET_STRING_ELT(names, (R_xlen_t)c,
                               Rf_mkCharLenCE(buf, (int)f->name_len + k, CE_UTF8));
            }
        }
        UNPROTECT(1);
    }
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 3));
    SET_VECTOR_ELT(out, 0, cols);
    SET_VECTOR_ELT(out, 1, names);
    SET_VECTOR_ELT(out, 2, descrs);
    UNPROTECT(4);
    return out;
}

static SEXP build(const uint8_t *data, const znp_plan *plan, const znp_opts *o,
                  znp_build_fault *fault)
{
    fault->status = ZNP_BUILD_OK;
    fault->index = 0;
    fault->dim = -1;

    /* R's dim is integer; a vector may be long (design 6.2). */
    if (plan->ndim >= 2)
        for (int j = 0; j < plan->ndim; j++)
            if (plan->shape[j] > INT_MAX) {
                fault->status = ZNP_BUILD_UNREPRESENTABLE;
                fault->dim = j;
                return R_NilValue;
            }
    if (plan->count > (uint64_t)R_XLEN_T_MAX) {
        fault->status = ZNP_BUILD_UNREPRESENTABLE;
        fault->dim = 0;
        return R_NilValue;
    }

    const uint8_t *body = data + plan->data_offset;
    if (plan->structured)
        return build_records(body, plan, o, fault);

    size_t n = (size_t)plan->count;
    SEXP out = read_column(body, n, (size_t)plan->itemsize, &plan->dtype, o, fault);
    if (fault->status != ZNP_BUILD_OK)
        return R_NilValue;
    PROTECT(out);
    SEXPTYPE rtype = TYPEOF(out);

    int k = plan->ndim;
    if (k >= 2) {
        int c_order = !plan->fortran_order;
        if (c_order && !o->order_file && (rtype == STRSXP || rtype == VECSXP)) {
            SEXP perm = PROTECT(permute_elements(out, plan->shape, k));
            Rf_setAttrib(perm, R_DimSymbol, dim_attr(plan->shape, k, 0));
            UNPROTECT(2);
            return perm;
        }
        if (c_order && !o->order_file) {
            SEXP perm = PROTECT(Rf_allocVector(rtype, (R_xlen_t)n));
            size_t width = rtype == CPLXSXP ? sizeof(Rcomplex)
                         : rtype == REALSXP ? sizeof(double) : sizeof(int);
            znp_permute(znp_dataptr(out), znp_dataptr(perm), width, n, plan->shape, k, 1);
            Rf_setAttrib(perm, R_DimSymbol, dim_attr(plan->shape, k, 0));
            UNPROTECT(2);
            return perm;
        }
        Rf_setAttrib(out, R_DimSymbol, dim_attr(plan->shape, k, c_order));
    }
    UNPROTECT(1);
    return out;
}

/* opts: c(order_file, as_integer64, na_allow, strings_raw, encoding,
   datetime_raw). Returns list(status, offset, index, value, descr,
   native_order, align64, dim, shape); status is a check or a build status
   name, and R raises. For a structured dtype, value is list(columns, names,
   descrs) and R makes the data frame; shape is in R's order (reversed for
   a C-order file read with order = "file"). */
SEXP zunpy_decode(SEXP x, SEXP limits, SEXP opts)
{
    znp_limits lim;
    znp_limits_from_r(limits, &lim);
    znp_opts o;
    o.order_file = INTEGER(opts)[0];
    o.as_integer64 = INTEGER(opts)[1];
    o.na_allow = INTEGER(opts)[2];
    o.strings_raw = INTEGER(opts)[3];
    o.encoding = INTEGER(opts)[4];
    o.datetime_raw = INTEGER(opts)[5];

    const uint8_t *data = RAW(x);
    size_t size = (size_t)XLENGTH(x);
    znp_plan plan;
    znp_fault cf;
    size_t need = 0;
    znp_status st = znp_check_prefix(data, size, &lim, &plan, &need, &cf);
    if (st == ZNP_OK) {
        void *scratch = R_alloc(need, 8);
        st = znp_check(data, size, &lim, scratch, need, &plan, &cf);
    }

    SEXP out = PROTECT(Rf_allocVector(VECSXP, 9));
    const char *names[] = {"status", "offset", "index", "value", "descr",
                           "native_order", "align64", "dim", "shape"};
    SEXP nm = PROTECT(Rf_allocVector(STRSXP, 9));
    for (int i = 0; i < 9; i++)
        SET_STRING_ELT(nm, i, Rf_mkChar(names[i]));
    Rf_setAttrib(out, R_NamesSymbol, nm);

    if (st != ZNP_OK) {
        SET_VECTOR_ELT(out, 0, Rf_mkString(znp_status_name(st)));
        SET_VECTOR_ELT(out, 1, Rf_ScalarReal((double)cf.offset));
        UNPROTECT(2);
        return out;
    }

    SET_VECTOR_ELT(out, 4, znp_descr_sexp(&plan));
    SET_VECTOR_ELT(out, 5, Rf_ScalarLogical(plan.native_order));
    SET_VECTOR_ELT(out, 6, Rf_ScalarLogical(plan.align64));
    SEXP shape = PROTECT(Rf_allocVector(REALSXP, plan.ndim));
    for (int j = 0; j < plan.ndim; j++)
        REAL(shape)[j] = (double)plan.shape[(o.order_file && !plan.fortran_order)
                                            ? plan.ndim - 1 - j : j];
    SET_VECTOR_ELT(out, 8, shape);
    UNPROTECT(1);

    znp_build_fault bf;
    SEXP value = PROTECT(build(data, &plan, &o, &bf));
    SET_VECTOR_ELT(out, 0, Rf_mkString(build_status_name(bf.status)));
    if (bf.status != ZNP_BUILD_OK) {
        double off = (double)plan.data_offset + (double)bf.index * (double)plan.itemsize;
        SET_VECTOR_ELT(out, 1, Rf_ScalarReal(bf.dim >= 0 ? (double)plan.header_offset : off));
        SET_VECTOR_ELT(out, 2, Rf_ScalarReal(bf.dim >= 0 ? NA_REAL : (double)bf.index + 1));
        SET_VECTOR_ELT(out, 7, Rf_ScalarInteger(bf.dim >= 0 ? bf.dim + 1 : NA_INTEGER));
    } else
        SET_VECTOR_ELT(out, 3, value);
    UNPROTECT(3);
    return out;
}
