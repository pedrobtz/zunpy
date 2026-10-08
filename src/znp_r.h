#ifndef ZNP_R_H
#define ZNP_R_H

#define R_NO_REMAP
#include <Rinternals.h>

/* .Call entry points, registered in init.c. */
SEXP zunpy_build_info(void);

#endif /* ZNP_R_H */
