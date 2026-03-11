/*
 * tunctl — create and manage TUN/TAP network devices
 *
 * Usage:
 *   tunctl -t <dev> [-u <uid>]  — create TAP device owned by uid
 *   tunctl -d <dev>             — delete TAP device
 *
 * Requires CAP_NET_ADMIN / root. Embedded for convenience but will
 * only work when kernel is run with appropriate privileges.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <pwd.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <linux/if_tun.h>

static int tun_open(const char *dev, int flags)
{
    struct ifreq ifr;
    int fd, err;

    fd = open("/dev/net/tun", O_RDWR);
    if (fd < 0) { perror("/dev/net/tun"); return -1; }

    memset(&ifr, 0, sizeof(ifr));
    ifr.ifr_flags = flags;
    strncpy(ifr.ifr_name, dev, IFNAMSIZ-1);

    err = ioctl(fd, TUNSETIFF, &ifr);
    if (err < 0) { perror("TUNSETIFF"); close(fd); return -1; }
    return fd;
}

int main(int argc, char *argv[])
{
    int opt, fd, del = 0;
    char *dev = NULL;
    uid_t owner = getuid();
    struct passwd *pw;

    while ((opt = getopt(argc, argv, "t:d:u:")) != -1) {
        switch (opt) {
        case 't': dev = optarg; del = 0; break;
        case 'd': dev = optarg; del = 1; break;
        case 'u':
            pw = getpwnam(optarg);
            if (pw) owner = pw->pw_uid;
            else    owner = (uid_t)atoi(optarg);
            break;
        default:
            fprintf(stderr, "Usage: tunctl -t <dev> [-u uid] | -d <dev>\n");
            return 1;
        }
    }

    if (!dev) {
        fprintf(stderr, "Usage: tunctl -t <dev> [-u uid] | -d <dev>\n");
        return 1;
    }

    fd = tun_open(dev, IFF_TAP | IFF_NO_PI);
    if (fd < 0) return 1;

    if (del) {
        if (ioctl(fd, TUNSETPERSIST, 0) < 0) { perror("TUNSETPERSIST 0"); }
        else printf("Set '%s' nonpersistent\n", dev);
    } else {
        if (ioctl(fd, TUNSETOWNER, owner) < 0) { perror("TUNSETOWNER"); }
        if (ioctl(fd, TUNSETPERSIST, 1) < 0)   { perror("TUNSETPERSIST 1"); }
        else printf("Set '%s' persistent and owned by uid %d\n", dev, owner);
    }

    close(fd);
    return 0;
}
