// SPDX-License-Identifier: GPL-2.0
/*
 * UML embedded helper extraction - stub implementation.
 * Helpers are expected to be found via PATH or explicit env vars.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

char uml_helpers_dir[256] = "";

void uml_helpers_extract(const char *umid)
{
	/* Helpers are provided externally via PATH or env vars. */
	(void)umid;
}

void uml_helpers_cleanup(void)
{
	/* Nothing to clean up. */
}
