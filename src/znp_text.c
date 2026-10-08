/*
 * znp_text.c -- S<n>, U<n> and V<n> elements (design 6.1, 7.1).
 *
 * Reading: S is NUL-padded bytes, U is NUL-padded UCS-4 code points in the
 * file's byte order, V is opaque bytes. Trailing NULs are stripped, as
 * NumPy strips them; a NUL inside a value cannot live in an R string, so it
 * is refused unless the bytes are returned raw. Writing: UTF-8 R strings to
 * U (code points) or S (bytes), NUL-padded to the width.
 *
 * Statuses only; R/decode.R and R/encode.R raise (design 11).
 */
#include <limits.h>
#include <string.h>

#include <zubin.h>
#include <zufast/utf8.h>

#include "znp_r.h"

/* Code point to UTF-8; returns the byte count (cp already validated). */
static int utf8_put(char *out, uint32_t cp)
{
    if (cp < 0x80) {
        out[0] = (char)cp;
        return 1;
    }
    if (cp < 0x800) {
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (char)(0xF0 | (cp >> 18));
    out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[3] = (char)(0x80 | (cp & 0x3F));
    return 4;
}

/* The next code point of valid UTF-8 at *p, advancing it. */
static uint32_t utf8_next(const unsigned char **p)
{
    const unsigned char *s = *p;
    uint32_t cp;
    if (s[0] < 0x80) {
        cp = s[0];
        *p += 1;
    } else if (s[0] < 0xE0) {
        cp = ((uint32_t)(s[0] & 0x1F) << 6) | (s[1] & 0x3F);
        *p += 2;
    } else if (s[0] < 0xF0) {
        cp = ((uint32_t)(s[0] & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6) | (s[2] & 0x3F);
        *p += 3;
    } else {
        cp = ((uint32_t)(s[0] & 0x07) << 18) | ((uint32_t)(s[1] & 0x3F) << 12) |
             ((uint32_t)(s[2] & 0x3F) << 6) | (s[3] & 0x3F);
        *p += 4;
    }
    return cp;
}

/* ---- reading ------------------------------------------------------------ */

/* n elements of S<width> or V<width>, `stride` bytes apart, as a list of
   raw vectors; trailing NULs stripped for S. */
SEXP znp_read_bytes(const uint8_t *base, size_t n, size_t stride, size_t width,
                    int strip)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, (R_xlen_t)n));
    for (size_t i = 0; i < n; i++) {
        const uint8_t *p = base + i * stride;
        size_t len = width;
        if (strip)
            while (len > 0 && p[len - 1] == 0)
                len--;
        SEXP r = Rf_allocVector(RAWSXP, (R_xlen_t)len);
        SET_VECTOR_ELT(out, (R_xlen_t)i, r);
        if (len)
            memcpy(RAW(r), p, len);
        if (i % 65536 == 65535)
            R_CheckUserInterrupt();
    }
    UNPROTECT(1);
    return out;
}

/* n elements of S<width> as strings. encoding: 0 UTF-8 (validated), 1
   Latin-1 (converted to UTF-8), 2 bytes (marked as bytes). On a refusal,
   *bad is the element and the return is R_NilValue with *status set:
   1 a NUL inside a value, 2 not valid UTF-8, 3 a string longer than R
   allows. */
SEXP znp_read_s(const uint8_t *base, size_t n, size_t stride, size_t width,
                int encoding, int *status, size_t *bad)
{
    SEXP out = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)n));
    char *buf = encoding == 1 ? R_alloc(2 * width + 1, 1) : NULL;
    *status = 0;
    for (size_t i = 0; i < n; i++) {
        const char *p = (const char *)base + i * stride;
        size_t len = width;
        while (len > 0 && p[len - 1] == 0)
            len--;
        if (memchr(p, 0, len) != NULL) {
            *status = 1;
            *bad = i;
            UNPROTECT(1);
            return R_NilValue;
        }
        SEXP s;
        if (encoding == 0) {
            if (!zuf_utf8_valid(p, len)) {
                *status = 2;
                *bad = i;
                UNPROTECT(1);
                return R_NilValue;
            }
            if (len > INT_MAX) {
                *status = 3;
                *bad = i;
                UNPROTECT(1);
                return R_NilValue;
            }
            s = Rf_mkCharLenCE(p, (int)len, CE_UTF8);
        } else if (encoding == 1) {
            size_t k = 0;
            for (size_t j = 0; j < len; j++)
                k += (size_t)utf8_put(buf + k, (unsigned char)p[j]);
            if (k > INT_MAX) {
                *status = 3;
                *bad = i;
                UNPROTECT(1);
                return R_NilValue;
            }
            s = Rf_mkCharLenCE(buf, (int)k, CE_UTF8);
        } else {
            if (len > INT_MAX) {
                *status = 3;
                *bad = i;
                UNPROTECT(1);
                return R_NilValue;
            }
            s = Rf_mkCharLenCE(p, (int)len, CE_BYTES);
        }
        SET_STRING_ELT(out, (R_xlen_t)i, s);
        if (i % 65536 == 65535)
            R_CheckUserInterrupt();
    }
    UNPROTECT(1);
    return out;
}

/* n elements of U<chars> (UCS-4, big_endian or not) as UTF-8 strings.
   *status: 1 a NUL inside a value, 2 a surrogate or a code point above
   U+10FFFF, 3 a string longer than R allows. */
SEXP znp_read_u(const uint8_t *base, size_t n, size_t stride, size_t chars,
                int big_endian, int *status, size_t *bad)
{
    SEXP out = PROTECT(Rf_allocVector(STRSXP, (R_xlen_t)n));
    char *buf = R_alloc(4 * chars + 1, 1);
    *status = 0;
    for (size_t i = 0; i < n; i++) {
        const uint8_t *p = base + i * stride;
        size_t len = chars;
        while (len > 0 && (big_endian ? zb_rd_u32be(p + 4 * (len - 1))
                                      : zb_rd_u32le(p + 4 * (len - 1))) == 0)
            len--;
        size_t k = 0;
        for (size_t j = 0; j < len; j++) {
            uint32_t cp = big_endian ? zb_rd_u32be(p + 4 * j) : zb_rd_u32le(p + 4 * j);
            if (cp == 0 || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
                *status = cp == 0 ? 1 : 2;
                *bad = i;
                UNPROTECT(1);
                return R_NilValue;
            }
            k += (size_t)utf8_put(buf + k, cp);
        }
        if (k > INT_MAX) {
            *status = 3;
            *bad = i;
            UNPROTECT(1);
            return R_NilValue;
        }
        SET_STRING_ELT(out, (R_xlen_t)i, Rf_mkCharLenCE(buf, (int)k, CE_UTF8));
        if (i % 65536 == 65535)
            R_CheckUserInterrupt();
    }
    UNPROTECT(1);
    return out;
}

/* ---- writing ------------------------------------------------------------ */

/* The width a character vector needs: the most code points (U) or bytes
   (S) of any element. x is UTF-8 or bytes, NA already replaced. */
size_t znp_text_width(SEXP x, int as_u)
{
    size_t w = 0;
    R_xlen_t n = XLENGTH(x);
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(x, i);
        size_t len = (size_t)LENGTH(s);
        if (as_u) {
            bool valid;
            len = zuf_utf8_count(CHAR(s), len, &valid);
        }
        if (len > w)
            w = len;
    }
    return w;
}

/* Writes x into n elements of `width` (code points for U, bytes for S),
   `stride` bytes apart. Returns 0, or 1 with *bad when an element is longer
   than the width, or 2 when an element is not valid UTF-8 (U only). */
int znp_write_text(SEXP x, uint8_t *dst, size_t stride, size_t width, int as_u,
                   size_t *bad)
{
    R_xlen_t n = XLENGTH(x);
    size_t item = as_u ? 4 * width : width;
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(x, i);
        const char *c = CHAR(s);
        size_t len = (size_t)LENGTH(s);
        uint8_t *p = dst + (size_t)i * stride;
        memset(p, 0, item);
        if (as_u) {
            if (!zuf_utf8_valid(c, len)) {
                *bad = (size_t)i;
                return 2;
            }
            const unsigned char *q = (const unsigned char *)c, *end = q + len;
            size_t j = 0;
            while (q < end) {
                if (j == width) {
                    *bad = (size_t)i;
                    return 1;
                }
                zb_wr_u32le(p + 4 * j, utf8_next(&q));
                j++;
            }
        } else {
            if (len > width) {
                *bad = (size_t)i;
                return 1;
            }
            memcpy(p, c, len);
        }
    }
    return 0;
}
