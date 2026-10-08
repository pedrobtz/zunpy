#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

#include "znp_r.h"

/* The .Call table. Entry points arrive with the stages that need them
   (roadmap); R_useDynamicSymbols(FALSE) keeps anything not listed here
   unreachable by name. */
static const R_CallMethodDef CallEntries[] = {
    {"zunpy_build_info", (DL_FUNC) &zunpy_build_info, 0},
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
