#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "znp_r.h"

/* The .Call table. Entry points arrive with the stages that need them
   (roadmap); R_useDynamicSymbols(FALSE) keeps anything not listed here
   unreachable by name. */
static const R_CallMethodDef CallEntries[] = {
    {"zunpy_build_info",   (DL_FUNC) &zunpy_build_info,   0},
    {"zunpy_fast_path",    (DL_FUNC) &zunpy_fast_path,    0},
    {"zunpy_header_check", (DL_FUNC) &zunpy_header_check, 2},
    {"zunpy_decode",       (DL_FUNC) &zunpy_decode,       3},
    {"zunpy_encode",       (DL_FUNC) &zunpy_encode,       4},
    {"zunpy_encode_records", (DL_FUNC) &zunpy_encode_records, 6},
    {"zunpy_zip_members",  (DL_FUNC) &zunpy_zip_members,  2},
    {"zunpy_crc32",        (DL_FUNC) &zunpy_crc32,        1},
    {"zunpy_slice",        (DL_FUNC) &zunpy_slice,        3},
    {"zunpy_zip_build",    (DL_FUNC) &zunpy_zip_build,    5},
    {NULL, NULL, 0}
};

/* attribute_visible: Makevars builds with $(C_VISIBILITY), which hides
   every other symbol; R must still find this one. */
void attribute_visible R_init_zunpy(DllInfo *dll)
{
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
