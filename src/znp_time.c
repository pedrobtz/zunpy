/*
 * znp_time.c -- datetime64 and timedelta64 counts (design 6.1, 7.1, D7).
 *
 * A count of `scale` ticks per R unit becomes the double nearest to
 * count / scale (count_to_units() says how); NaT (INT64_MIN) becomes NA. Writing inverts it and
 * accepts a value only when its count reads back as the same double:
 * exact up to what the double holds, and a finer fraction is refused,
 * never rounded. Statuses only; R raises.
 */
#include <math.h>
#include <string.h>

#include <zubin.h>

#include "znp_r.h"

int64_t znp_time_scale(char kind, const char *unit)
{
    if (strcmp(unit, "D") == 0 || strcmp(unit, "s") == 0) return 1;
    if (strcmp(unit, "ms") == 0) return 1000;
    if (strcmp(unit, "us") == 0) return 1000000;
    if (strcmp(unit, "ns") == 0) return 1000000000;
    if (kind == 'm' && (strcmp(unit, "m") == 0 || strcmp(unit, "h") == 0 ||
                        strcmp(unit, "W") == 0))
        return 1;
    return 0;
}

/* Up to 2^53 the count is exact as a double and one division rounds
   correctly; beyond, the whole units are split off first so that they stay
   exact and only the fraction is rounded. */
static double count_to_units(int64_t r, int64_t scale)
{
    const int64_t lim = (int64_t)1 << 53;
    if (scale == 1 || (r <= lim && r >= -lim))
        return (double)r / (double)scale;
    int64_t q = r / scale, rem = r % scale;
    return (double)q + (double)rem / (double)scale;
}

/* Reads n int64 counts (file byte order) into dst as R units: NaT is
   NA_REAL. With scale 1 a count beyond 2^53 in magnitude is refused (*bad),
   since the double would not be exact; with a larger scale the result is
   the nearest double, which design 6.1 documents. Returns 0 or 1. */
int znp_read_counts(const uint8_t *base, size_t n, int big_endian,
                    int64_t scale, double *dst, size_t *bad)
{
    const int64_t lim = (int64_t)1 << 53;
    for (size_t i = 0; i < n; i++) {
        const uint8_t *p = base + 8 * i;
        int64_t r = big_endian ? zb_rd_i64be(p) : zb_rd_i64le(p);
        if (r == INT64_MIN) {
            dst[i] = NA_REAL;
            continue;
        }
        if (scale == 1 && (r > lim || r < -lim)) {
            *bad = i;
            return 1;
        }
        dst[i] = count_to_units(r, scale);
    }
    return 0;
}

/* The count of `scale` ticks per unit for x, or 0 when there is none that
   reads back as x. */
static int units_to_count(double x, int64_t scale, int64_t *out)
{
    const double top = 9223372036854775807.0;
    if (!isfinite(x))
        return 0;
    double whole = floor(x);
    if (fabs(whole) * (double)scale >= top)
        return 0;
    double frac = x - whole;            /* exact: x and whole share an exponent range */
    int64_t r = (int64_t)whole * scale + (int64_t)llround(frac * (double)scale);
    /* The nearest count can be one off after the rounding of frac * scale. */
    for (int d = 0; d < 3; d++) {
        int64_t c = r + (d == 0 ? 0 : d == 1 ? 1 : -1);
        if (c != INT64_MIN && count_to_units(c, scale) == x) {
            *out = c;
            return 1;
        }
    }
    return 0;
}

/* Writes x (R units, NA as NaT) as int64 counts, little-endian. Returns 0,
   or 1 with *bad when a value has no exact count. */
int znp_write_counts(const double *x, size_t n, int64_t scale, uint8_t *dst,
                     size_t *bad)
{
    for (size_t i = 0; i < n; i++) {
        int64_t c;
        if (ISNAN(x[i]))
            c = INT64_MIN;
        else if (!units_to_count(x[i], scale, &c)) {
            *bad = i;
            return 1;
        }
        zb_wr_i64le(dst + 8 * i, c);
    }
    return 0;
}
