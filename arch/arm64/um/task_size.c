// SPDX-License-Identifier: GPL-2.0
/*
 * arch/arm64/um/task_size.c
 *
 * Detect host VA size at runtime by probing mmap near candidate boundaries.
 * arm64 hosts use either 39-bit (512 GB) or 48-bit (256 TB) user VA.
 * Hardcoding 39-bit breaks on 48-bit hosts (e.g. most CI runners).
 */
#include <os.h>
#include <sys/mman.h>
#include <unistd.h>

unsigned long os_get_top_address(void)
{
	/*
	 * Probe whether the host supports 48-bit VA by attempting mmap
	 * near the 48-bit boundary. If it succeeds, host is 48-bit.
	 * Fall back to 39-bit if it fails.
	 *
	 * We use MAP_FIXED_NOREPLACE so we don't clobber anything.
	 * A simple heuristic: try to map 1 page at (1UL<<47) - PAGE_SIZE.
	 */
	long page_size = sysconf(_SC_PAGE_SIZE);
	unsigned long probe_48 = (1UL << 47) - page_size;
	void *ret;

	ret = mmap((void *)probe_48, page_size,
		   PROT_NONE,
		   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE,
		   -1, 0);
	if (ret != MAP_FAILED) {
		munmap(ret, page_size);
		return (1UL << 48); /* 48-bit VA host */
	}

	return (1UL << 39); /* 39-bit VA host */
}
