// SPDX-License-Identifier: GPL-2.0
/*
 * UML vsyscall stubs - provide empty implementations for vsyscall functions
 * that UML doesn't need (arm64 doesn't have vsyscall, x86 uses a different mechanism)
 */

#include <linux/timekeeper_internal.h>

void update_vsyscall(struct timekeeper *tk)
{
	/* UML doesn't use vsyscall - this is a stub */
}
EXPORT_SYMBOL(update_vsyscall);

void update_vsyscall_tz(void)
{
	/* UML doesn't use vsyscall - this is a stub */
}
EXPORT_SYMBOL(update_vsyscall_tz);
