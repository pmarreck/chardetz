/* Translate-C entry point for the differential oracle test.
 *
 * Zig 0.16 deprecates source-level `@cImport`; the idiomatic replacement is a
 * `b.addTranslateC` step in build.zig pointed at a header that #includes the C
 * surface we want exposed. This header pulls in uchardet's 6-function C API
 * (uchardet_new/_delete/_handle_data/_data_end/_reset/_get_charset). The
 * uchardetz `src/` directory is added as an include path on the translate-c
 * step in build.zig, so the bare name resolves. */
#include "uchardet.h"
