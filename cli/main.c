/* chardetz command-line tool. It reaches the detector only through the
 * uchardet C ABI (include/uchardet.h), the same way any C consumer would.
 *
 * Plain output matches the uchardet CLI: the charset name (or "unknown"),
 * prefixed with "FILE: " when several inputs are given.
 *
 * SPDX-License-Identifier: MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "uchardet.h"

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#ifndef CHARDETZ_VERSION
#define CHARDETZ_VERSION "unknown"
#endif

/* Same read size as the uchardet CLI, so chunk-dependent results match. */
#define BUFFER_SIZE 65536

#if defined(__APPLE__)
#define CHARDETZ_OS "macos"
#elif defined(_WIN32)
#define CHARDETZ_OS "windows"
#elif defined(__linux__)
#define CHARDETZ_OS "linux"
#elif defined(__wasi__)
#define CHARDETZ_OS "wasi"
#else
#define CHARDETZ_OS "unknown-os"
#endif

#if defined(__aarch64__) || defined(_M_ARM64)
#define CHARDETZ_ARCH "aarch64"
#elif defined(__x86_64__) || defined(_M_X64)
#define CHARDETZ_ARCH "x86_64"
#elif defined(__wasm32__)
#define CHARDETZ_ARCH "wasm32"
#else
#define CHARDETZ_ARCH "unknown-arch"
#endif

static char buffer[BUFFER_SIZE];

static void show_usage(FILE *out)
{
	fputs("chardetz: detect the character encoding of files (pure-Zig uchardet)\n"
	      "\n"
	      "Usage: chardetz [options] [FILE...]\n"
	      "  With no FILE, or when FILE is - or @stdin, read standard input.\n"
	      "\n"
	      "Options:\n"
	      "  -h, --help     show this help\n"
	      "  -v, --version  show version information\n"
	      "      --about    one-line description, version and platform\n"
	      "      --json     one JSON object per input: {\"file\":...,\"charset\":...}\n"
	      "                 (charset is null when no encoding was detected)\n"
	      "  --             treat every following argument as a FILE\n"
	      "\n"
	      "Output matches the uchardet tool: the charset name, or \"unknown\",\n"
	      "prefixed with \"FILE: \" when more than one input is given.\n",
	      out);
}

static void show_version(void)
{
	printf("chardetz %s\n", CHARDETZ_VERSION);
	printf("Translated from uchardet (Mozilla universalchardet lineage); MPL 1.1 / GPL 2.0+ / LGPL 2.1+\n");
}

static void show_about(void)
{
	printf("chardetz %s: character-encoding detector, a pure-Zig translation of uchardet (%s %s)\n",
	       CHARDETZ_VERSION, CHARDETZ_OS, CHARDETZ_ARCH);
}

/* Writes s as a JSON string literal; UTF-8 passes through unchanged. */
static void json_string(const char *s)
{
	putchar('"');
	for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
		if (*p == '"' || *p == '\\')
			printf("\\%c", *p);
		else if (*p < 0x20)
			printf("\\u%04x", *p);
		else
			putchar(*p);
	}
	putchar('"');
}

/* Feeds fp to the detector in BUFFER_SIZE chunks, exactly like the uchardet
 * CLI (including its final zero-length call at end of file). Returns 0 on
 * success. */
static int detect(uchardet_t ud, FILE *fp, const char **charset)
{
	uchardet_reset(ud);
	while (!feof(fp)) {
		size_t len = fread(buffer, 1, BUFFER_SIZE, fp);
		if (ferror(fp))
			return -1;
		if (uchardet_handle_data(ud, buffer, len) != 0) {
			fputs("chardetz: out of memory while handling data\n", stderr);
			return -2;
		}
	}
	uchardet_data_end(ud);
	*charset = uchardet_get_charset(ud);
	return 0;
}

static int is_stdin_name(const char *name)
{
	return strcmp(name, "-") == 0 || strcmp(name, "@stdin") == 0;
}

int main(int argc, char **argv)
{
	int json = 0;
	int files_only = 0;
	int nfiles = 0;
	const char **files = calloc((size_t)argc + 1, sizeof *files);
	if (files == NULL) {
		fputs("chardetz: out of memory\n", stderr);
		return 1;
	}

	for (int i = 1; i < argc; i++) {
		const char *a = argv[i];
		if (files_only || a[0] != '-' || strcmp(a, "-") == 0) {
			files[nfiles++] = a;
		} else if (strcmp(a, "--") == 0) {
			files_only = 1;
		} else if (strcmp(a, "-h") == 0 || strcmp(a, "--help") == 0) {
			show_usage(stdout);
			free(files);
			return 0;
		} else if (strcmp(a, "-v") == 0 || strcmp(a, "--version") == 0) {
			show_version();
			free(files);
			return 0;
		} else if (strcmp(a, "--about") == 0) {
			show_about();
			free(files);
			return 0;
		} else if (strcmp(a, "--json") == 0) {
			json = 1;
		} else {
			fprintf(stderr, "chardetz: unknown option %s (see chardetz --help)\n", a);
			free(files);
			return 2;
		}
	}
	if (nfiles == 0)
		files[nfiles++] = "-";

#ifdef _WIN32
	_setmode(_fileno(stdin), _O_BINARY);
#endif

	uchardet_t ud = uchardet_new();
	if (ud == NULL) {
		fputs("chardetz: out of memory\n", stderr);
		free(files);
		return 1;
	}

	int error_seen = 0;
	for (int i = 0; i < nfiles; i++) {
		const char *name = files[i];
		int from_stdin = is_stdin_name(name);
		FILE *fp = from_stdin ? stdin : fopen(name, "rb");
		if (fp == NULL) {
			fprintf(stderr, "%s: %s\n", name, strerror(errno));
			error_seen = 1;
			continue;
		}
		const char *charset = NULL;
		int rc = detect(ud, fp, &charset);
		if (!from_stdin)
			fclose(fp);
		if (rc != 0) {
			if (rc == -1)
				fprintf(stderr, "%s: read error\n", name);
			error_seen = 1;
			continue;
		}
		if (json) {
			fputs("{\"file\":", stdout);
			json_string(from_stdin ? "-" : name);
			fputs(",\"charset\":", stdout);
			if (*charset)
				json_string(charset);
			else
				fputs("null", stdout);
			fputs("}\n", stdout);
		} else {
			if (nfiles > 1)
				printf("%s: ", name);
			printf("%s\n", *charset ? charset : "unknown");
		}
	}

	uchardet_delete(ud);
	free(files);
	return error_seen;
}
