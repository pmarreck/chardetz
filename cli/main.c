/* SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
 * chardetz CLI — dogfoods the uchardet-compatible C FFI.
 *
 * This program is a pure I/O adapter: it parses args, reads bytes from a file
 * (or stdin), feeds them THROUGH the C ABI (uchardet_handle_data / data_end),
 * and prints uchardet_get_charset. It deliberately calls the engine only via
 * the public C header — it never touches Zig directly — so building/running it
 * exercises the exact FFI boundary external consumers use.
 *
 * House CLI conventions: -h/--help, --about (one-line: name+version+platform+
 * arch), file path OR -/@stdin for stdin, charset to stdout, metadata/errors to
 * stderr, --json output, --simple/--no-color switches, later-args-override.
 */

#include "uchardet.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHARDETZ_VERSION "0.1.0"

/* Platform/arch strings resolved at compile time for --about. */
#if defined(__APPLE__)
#define CHARDETZ_OS "macos"
#elif defined(_WIN32)
#define CHARDETZ_OS "windows"
#elif defined(__linux__)
#define CHARDETZ_OS "linux"
#else
#define CHARDETZ_OS "unknown-os"
#endif

#if defined(__aarch64__) || defined(_M_ARM64)
#define CHARDETZ_ARCH "aarch64"
#elif defined(__x86_64__) || defined(_M_X64)
#define CHARDETZ_ARCH "x86_64"
#else
#define CHARDETZ_ARCH "unknown-arch"
#endif

static const char *PROG = "chardetz";

static void print_help(FILE *out) {
	fprintf(out,
		"%s %s — character-encoding detector (pure-Zig uchardet port)\n"
		"\n"
		"USAGE:\n"
		"  %s [OPTIONS] <FILE>\n"
		"  %s [OPTIONS] -          # read from stdin\n"
		"  %s [OPTIONS] @stdin     # read from stdin\n"
		"  cat file | %s -\n"
		"\n"
		"OPTIONS:\n"
		"  -h, --help        Show this help and exit\n"
		"      --about       One-line: name, version, platform, arch\n"
		"      --json        Emit JSON: {\"charset\":\"<NAME>\"}\n"
		"      --simple      Plain output, no decoration (currently a no-op alias)\n"
		"      --no-color    Disable ANSI color (currently a no-op alias)\n"
		"\n"
		"Detected charset is printed to stdout; diagnostics go to stderr.\n"
		"Later options override earlier ones.\n",
		PROG, CHARDETZ_VERSION, PROG, PROG, PROG, PROG);
}

static void print_about(FILE *out) {
	fprintf(out, "%s %s (%s/%s) — character-encoding detector, uchardet-compatible C ABI\n",
		PROG, CHARDETZ_VERSION, CHARDETZ_OS, CHARDETZ_ARCH);
}

/* Read an entire stream into a heap buffer. Returns 0 on success and sets
 * *out_buf / *out_len; caller frees. Returns non-zero on allocation failure. */
static int slurp(FILE *f, char **out_buf, size_t *out_len) {
	size_t cap = 1 << 16; /* 64 KiB initial */
	size_t len = 0;
	char *buf = (char *)malloc(cap);
	if (!buf) return 1;
	for (;;) {
		if (len == cap) {
			size_t ncap = cap * 2;
			char *nbuf = (char *)realloc(buf, ncap);
			if (!nbuf) { free(buf); return 1; }
			buf = nbuf;
			cap = ncap;
		}
		size_t got = fread(buf + len, 1, cap - len, f);
		len += got;
		if (got == 0) {
			if (feof(f)) break;
			if (ferror(f)) { free(buf); return 2; }
		}
	}
	*out_buf = buf;
	*out_len = len;
	return 0;
}

int main(int argc, char **argv) {
	int json = 0;
	const char *path = NULL; /* the positional file arg (NULL = none yet) */

	for (int i = 1; i < argc; i++) {
		const char *a = argv[i];
		if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
			print_help(stdout);
			return 0;
		} else if (strcmp(a, "--about") == 0) {
			print_about(stdout);
			return 0;
		} else if (strcmp(a, "--json") == 0) {
			json = 1;
		} else if (strcmp(a, "--simple") == 0 || strcmp(a, "--no-color") == 0) {
			/* Output is already plain text; accept these for house-convention
			 * compatibility (later: suppress any ANSI we add). */
		} else if (strcmp(a, "-") == 0 || strcmp(a, "@stdin") == 0) {
			path = a; /* stdin sentinel */
		} else if (a[0] == '-' && a[1] != '\0' && strcmp(a, "-") != 0) {
			fprintf(stderr, "%s: unknown option '%s' (try --help)\n", PROG, a);
			return 2;
		} else {
			path = a; /* positional file path (later args override) */
		}
	}

	if (path == NULL) {
		fprintf(stderr, "%s: no input file (give a path, or '-'/'@stdin'; try --help)\n", PROG);
		return 2;
	}

	FILE *f = NULL;
	int from_stdin = (strcmp(path, "-") == 0 || strcmp(path, "@stdin") == 0);
	if (from_stdin) {
		f = stdin;
	} else {
		f = fopen(path, "rb");
		if (!f) {
			fprintf(stderr, "%s: cannot open '%s'\n", PROG, path);
			return 1;
		}
	}

	char *buf = NULL;
	size_t len = 0;
	int rc = slurp(f, &buf, &len);
	if (!from_stdin) fclose(f);
	if (rc != 0) {
		fprintf(stderr, "%s: read error (%s)\n", PROG, rc == 1 ? "out of memory" : "I/O");
		free(buf);
		return 1;
	}

	uchardet_t ud = uchardet_new();
	if (!ud) {
		fprintf(stderr, "%s: failed to create detector (out of memory)\n", PROG);
		free(buf);
		return 1;
	}

	if (len > 0 && uchardet_handle_data(ud, buf, len) != 0) {
		fprintf(stderr, "%s: detector rejected input\n", PROG);
		uchardet_delete(ud);
		free(buf);
		return 1;
	}
	uchardet_data_end(ud);
	const char *charset = uchardet_get_charset(ud);

	if (json) {
		printf("{\"charset\":\"%s\"}\n", charset);
	} else {
		printf("%s\n", charset);
	}

	uchardet_delete(ud);
	free(buf);
	return 0;
}
