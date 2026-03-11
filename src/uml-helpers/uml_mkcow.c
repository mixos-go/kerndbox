/*
 * uml_mkcow — Create a UML copy-on-write (COW) backing file
 *
 * Usage: uml_mkcow <cow-file> <backing-file>
 *
 * Creates a COW file that records only the differences from the backing file.
 * The UML UBD driver then uses: ubd0=cow-file,backing-file
 *
 * COW file format (UML v2 COW header):
 *   magic[7]    "LinuCow"
 *   version[4]  = 2
 *   backing_file[1024]  path to backing file
 *   mtime[8]    backing file mtime
 *   size[8]     backing file size in bytes
 *   sectorsize[4] = 512
 *   alignment[4] (unused, = 0)
 *   bitmap_offset[4]  offset of bitmap in COW file
 *   -- then bitmap, then data sectors --
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <stdint.h>
#include <time.h>

#define COW_MAGIC    "LinuCow"
#define COW_VERSION  2
#define SECTOR_SIZE  512

struct cow_header_v2 {
    char     magic[8];
    uint32_t version;
    char     backing_file[1024];
    uint64_t mtime;
    uint64_t size;
    uint32_t sectorsize;
    uint32_t alignment;
    uint32_t bitmap_offset;
} __attribute__((packed));

int main(int argc, char *argv[])
{
    struct cow_header_v2 hdr;
    struct stat st;
    int fd;
    uint32_t bitmap_offset, nsectors, bitmap_bytes;

    if (argc != 3) {
        fprintf(stderr, "Usage: uml_mkcow <cow-file> <backing-file>\n");
        return 1;
    }

    if (stat(argv[2], &st) < 0) {
        perror(argv[2]);
        return 1;
    }

    nsectors     = (st.st_size + SECTOR_SIZE - 1) / SECTOR_SIZE;
    bitmap_bytes = (nsectors + 7) / 8;
    bitmap_offset = sizeof(hdr);

    memset(&hdr, 0, sizeof(hdr));
    memcpy(hdr.magic, COW_MAGIC, strlen(COW_MAGIC));
    hdr.version       = COW_VERSION;
    strncpy(hdr.backing_file, argv[2], sizeof(hdr.backing_file)-1);
    hdr.mtime         = (uint64_t)st.st_mtime;
    hdr.size          = (uint64_t)st.st_size;
    hdr.sectorsize    = SECTOR_SIZE;
    hdr.alignment     = 0;
    hdr.bitmap_offset = bitmap_offset;

    fd = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) { perror(argv[1]); return 1; }

    write(fd, &hdr, sizeof(hdr));

    /* Write zeroed bitmap (all sectors unmodified) */
    char *zeros = calloc(1, bitmap_bytes);
    write(fd, zeros, bitmap_bytes);
    free(zeros);
    close(fd);

    printf("Created COW file: %s\n", argv[1]);
    printf("  Backing: %s (%llu bytes, %u sectors)\n",
           argv[2], (unsigned long long)st.st_size, nsectors);
    return 0;
}
