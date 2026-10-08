/*
 * znp_check.h -- the check phase's R-free interface (design 4, 9, 12).
 *
 * The check phase reads a whole .npy held in memory, parses and validates
 * its header, compares the declared size with the bytes present, and
 * returns a plan. Nothing in it includes R's headers, so the fuzz build
 * (-DZNP_STANDALONE) compiles it alone.
 *
 * Memory: the check never allocates. It runs in two calls so that the
 * caller can size the scratch from a length the first call has already
 * bounded by max_header and by the bytes present:
 *
 *     znp_plan plan;
 *     znp_fault fault;
 *     size_t need;
 *     if (znp_check_prefix(data, size, &limits, &plan, &need, &fault)) ...
 *     void *scratch = R_alloc(need, 1);         -- or malloc() when fuzzing
 *     if (znp_check(data, size, &limits, scratch, need, &plan, &fault)) ...
 *
 * On success every size in the plan has been checked against `size`, so
 * the build phase may allocate from the plan alone (design 12).
 */
#ifndef ZNP_CHECK_H
#define ZNP_CHECK_H

#include <stddef.h>
#include <stdint.h>

/* Statuses are reported to R by name (R/conditions.R maps each to a class);
   keep the names and znp_status_name() in step. ZNP_OK is 0. */
typedef enum {
    ZNP_OK = 0,
    ZNP_ERR_MAGIC,          /* not \x93NUMPY                           parse   */
    ZNP_ERR_VERSION,        /* major not 1-3, or minor not 0           parse   */
    ZNP_ERR_TRUNCATED,      /* fewer bytes than the prefix or data     parse   */
    ZNP_ERR_TRAILING,       /* bytes after the declared data           parse   */
    ZNP_ERR_ALIGN,          /* data offset not a multiple of 16        parse   */
    ZNP_ERR_ENCODING,       /* header not valid UTF-8 (version 3)      parse   */
    ZNP_ERR_SYNTAX,         /* outside the literal grammar (9.2)       parse   */
    ZNP_ERR_DEPTH,          /* literal nested deeper than 8            parse   */
    ZNP_ERR_KEY,            /* missing, unknown or duplicate key       parse   */
    ZNP_ERR_TYPE,           /* a value of the wrong type               parse   */
    ZNP_ERR_DESCR,          /* outside the descr grammar (9.3)         parse   */
    ZNP_ERR_SHAPE,          /* negative or too-large dimension         parse   */
    ZNP_ERR_LAYOUT,         /* fields overlap or exceed the itemsize   invalid */
    ZNP_ERR_UNSUPPORTED,    /* object, long double, nested records     unsupported */
    ZNP_ERR_SIZE_LIMIT,     /* input or declared size over max_size    limit   */
    ZNP_ERR_HEADER_LIMIT,   /* header length over max_header           limit   */
    ZNP_ERR_DIMS_LIMIT,     /* more dimensions than max_dims           limit   */
    ZNP_ERR_FIELDS_LIMIT,   /* more fields than max_fields             limit   */
    ZNP_ERR_SCRATCH         /* the caller's scratch is too small       internal */
} znp_status;

const char *znp_status_name(znp_status st);

/* Hard ceilings; the limits below may be lower, never higher. */
#define ZNP_MAX_DIMS_CAP    64     /* NumPy 2's own ceiling */
#define ZNP_MAX_SUBDIMS      8     /* dimensions of a subarray field */
#define ZNP_MAX_DEPTH        8     /* literal nesting (D12) */

typedef struct {
    uint64_t max_size;      /* bytes of the whole input */
    uint64_t max_header;    /* bytes of the header dict */
    int      max_dims;      /* 0 .. ZNP_MAX_DIMS_CAP */
    int      max_fields;    /* 1 .. */
    int      header_only;   /* 1: the input may stop after the header, as for
                               npy_header() on a file; the data is not compared */
} znp_limits;

/* Where and why the check stopped. offset is 0-based into the input. */
typedef struct {
    znp_status status;
    uint64_t   offset;
} znp_fault;

/* One scalar dtype (design 9.3). order is '<', '>' or '|' after
   normalisation: '=' and a missing order become '<' for multi-byte kinds
   (and set plan.native_order) and '|' for one-byte kinds. */
typedef struct {
    char     order;
    char     kind;          /* b i u f c S U V M m (a is read as S) */
    char     unit[3];       /* M and m only: "D", "s", "ms", ... NUL-terminated */
    uint64_t itemsize;      /* bytes; U<n> is 4n */
    uint64_t chars;         /* U and S: the declared n */
} znp_dtype;

typedef struct {
    const char *name;       /* UTF-8, NUL-terminated, in the scratch */
    size_t      name_len;
    const char *title;      /* NULL when the field has none */
    size_t      title_len;
    uint64_t    offset;     /* bytes from the start of the record */
    znp_dtype   dtype;
    int         ndim;       /* subarray dimensions, 0 for a scalar field */
    uint64_t    shape[ZNP_MAX_SUBDIMS];
    uint64_t    size;       /* itemsize times the subarray count */
} znp_field;

typedef struct {
    int        major, minor;
    uint64_t   header_offset;   /* where the dict starts: 10 or 12 */
    uint64_t   header_len;      /* the dict's declared length */
    uint64_t   data_offset;
    int        fortran_order;
    int        ndim;
    uint64_t   shape[ZNP_MAX_DIMS_CAP];
    uint64_t   count;           /* product of shape */
    uint64_t   itemsize;
    uint64_t   data_bytes;      /* count * itemsize, equal to size - data_offset */
    int        structured;      /* 0: dtype holds the type; 1: fields do */
    znp_dtype  dtype;
    int        n_fields;
    znp_field *fields;          /* in the scratch */
    int        native_order;    /* an '=' or missing byte order was read */
    int        align64;         /* the data offset is a multiple of 64 */
} znp_plan;

/* The prefix (design 9.1): magic, version, header length, alignment, and
   the header length against max_header and the bytes present. Fills the
   prefix fields of plan and the scratch size znp_check() needs. */
znp_status znp_check_prefix(const uint8_t *data, size_t size,
                            const znp_limits *lim, znp_plan *plan,
                            size_t *scratch_size, znp_fault *fault);

/* The whole check: the prefix again, the header grammar, the descr, the
   shape, the limits and the size comparison. */
znp_status znp_check(const uint8_t *data, size_t size,
                     const znp_limits *lim, void *scratch, size_t scratch_size,
                     znp_plan *plan, znp_fault *fault);

#endif /* ZNP_CHECK_H */
