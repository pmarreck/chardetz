/* C ABI contract test for chardetz's drop-in uchardet API (include/uchardet.h).
 * Exercises every function through the C header exactly as a uchardet
 * consumer would. Silent on success; reports each failed expectation. */
#include <stdio.h>
#include <string.h>
#include "uchardet.h"

static int failures = 0;

static void expect_str(const char *what, const char *got, const char *want)
{
	if (got == NULL || strcmp(got, want) != 0) {
		fprintf(stderr, "ffi_test: %s: got \"%s\", want \"%s\"\n", what, got ? got : "(null)", want);
		failures++;
	}
}

static void expect_int(const char *what, int got, int want)
{
	if (got != want) {
		fprintf(stderr, "ffi_test: %s: got %d, want %d\n", what, got, want);
		failures++;
	}
}

static const char *detect(uchardet_t ud, const char *data, size_t len)
{
	uchardet_reset(ud);
	expect_int("handle_data return", uchardet_handle_data(ud, data, len), 0);
	uchardet_data_end(ud);
	return uchardet_get_charset(ud);
}

int main(void)
{
	uchardet_t ud = uchardet_new();
	if (ud == NULL) {
		fprintf(stderr, "ffi_test: uchardet_new returned NULL\n");
		return 1;
	}

	/* Fresh handle: nothing reported yet. */
	expect_str("fresh handle", uchardet_get_charset(ud), "");
	uchardet_data_end(ud);
	expect_str("data_end without data", uchardet_get_charset(ud), "");

	expect_str("ascii", detect(ud, "hello, world", 12), "ASCII");
	expect_str("utf-8 bom", detect(ud, "\xEF\xBB\xBFhi", 5), "UTF-8");
	expect_str("utf-16le bom", detect(ud, "\xFF\xFEh\0i\0", 6), "UTF-16");
	expect_str("utf-32le bom", detect(ud, "\xFF\xFE\0\0h\0\0\0", 8), "UTF-32");

	/* Length-delimited: embedded NUL bytes are data, not terminators. */
	expect_str("embedded nul", detect(ud, "ab\0cd\0ef", 8), "ASCII");

	/* A zero-length call (NULL data) is accepted and changes nothing. */
	uchardet_reset(ud);
	expect_int("null data, zero length", uchardet_handle_data(ud, NULL, 0), 0);
	expect_int("data after empty call", uchardet_handle_data(ud, "plain text", 10), 0);
	uchardet_data_end(ud);
	expect_str("empty first call", uchardet_get_charset(ud), "ASCII");

	/* reset clears a previous result. */
	uchardet_reset(ud);
	expect_str("after reset", uchardet_get_charset(ud), "");

	/* Multi-chunk UTF-8 (a two-byte sequence split across calls). */
	uchardet_reset(ud);
	const char *utf8 = "na\xC3\xAFve caf\xC3\xA9 r\xC3\xA9sum\xC3\xA9 \xC3\xA9t\xC3\xA9 \xC3\xA0 la cr\xC3\xA8me";
	size_t n = strlen(utf8);
	expect_int("chunk 1", uchardet_handle_data(ud, utf8, 3), 0);
	expect_int("chunk 2", uchardet_handle_data(ud, utf8 + 3, n - 3), 0);
	uchardet_data_end(ud);
	expect_str("split utf-8", uchardet_get_charset(ud), "UTF-8");

	uchardet_delete(ud);
	uchardet_delete(NULL); /* like C++ delete of a null pointer: no-op */

	return failures == 0 ? 0 : 1;
}
