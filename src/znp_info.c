#include <string.h>

#include <zubin.h>
#include <zufast/bits.h>
#include <zufast/number.h>
#include <zufast/utf8.h>

#include "znp_r.h"

/* One call into each provider header zunpy uses (design 3), so that every
   CI leg proves LinkingTo resolves and the headers compile together. The
   result is reported by zunpy_info() as `selftest`. */
static int znp_providers_selftest(void)
{
    static const unsigned char le[4] = {0x2a, 0x00, 0x00, 0x00};
    static const char digits[] = "42";
    static const char utf8[] = "\xc3\xa9";   /* U+00E9 */
    int64_t n = 0;

    if (zb_rd_u32le(le) != 42u) return 0;
    if (zuf_load_le32(le) != 42u) return 0;
    if (zuf_parse_i64(digits, digits + 2, &n).status != ZUF_OK || n != 42)
        return 0;
    if (!zuf_utf8_valid(utf8, strlen(utf8))) return 0;
    return 1;
}

/* list(zubin, zufast, host_big_endian, selftest) for zunpy_info(). */
SEXP zunpy_build_info(void)
{
    SEXP out = PROTECT(Rf_allocVector(VECSXP, 4));
    SET_VECTOR_ELT(out, 0, Rf_mkString(ZUBIN_VERSION));
    SET_VECTOR_ELT(out, 1, Rf_mkString(ZUFAST_VERSION));
    SET_VECTOR_ELT(out, 2, Rf_ScalarLogical(zb_host_big_endian()));
    SET_VECTOR_ELT(out, 3, Rf_ScalarLogical(znp_providers_selftest()));
    UNPROTECT(1);
    return out;
}
