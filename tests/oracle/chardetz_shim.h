/* Test-only: describes one upstream table, constant or model exported by a
 * generated shim (see tools/gen_tables renderShim). Not part of chardetz. */
#ifndef CHARDETZ_SHIM_H
#define CHARDETZ_SHIM_H
#include <stddef.h>

enum { CHARDETZ_INT, CHARDETZ_FLOAT, CHARDETZ_ARRAY, CHARDETZ_SEQUENCE_MODEL, CHARDETZ_SM_MODEL };

typedef struct {
	const char *name;
	int kind;
	const void *ptr;
	size_t size;
	long long ival;
	double fval;
} chardetz_table_ref;

#endif
