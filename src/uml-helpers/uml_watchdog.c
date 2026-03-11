/*
 * uml_watchdog — UML hardware watchdog daemon
 *
 * Called by the kernel's harddog driver (arch/um/drivers/harddog_user.c)
 * in two modes:
 *
 *   -pid <pid>          Monitor UML process by PID. If UML hangs and stops
 *                       pinging us, kill it.
 *
 *   -mconsole <socket>  Monitor via mconsole socket. Receive pings from
 *                       kernel watchdog driver over the mconsole interface.
 *
 * Protocol (both modes):
 *   Parent (kernel) writes 1 byte to out_fd to ping us.
 *   We write 1 byte back to in_fd to acknowledge.
 *   If no ping within timeout, UML has hung → kill it.
 *
 * fd inheritance: kernel sets up two pipes and passes them to us.
 *   in_fd  = fd 3 (we read pings from kernel)
 *   out_fd = fd 4 (we write acks back to kernel)
 *
 * Must be statically linked for embedding in kernel ELF.
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>

#define WATCHDOG_TIMEOUT  60   /* seconds before declaring UML hung */
#define PING_FD           3    /* read pings from here */
#define ACK_FD            4    /* write acks here */

static pid_t watched_pid = 0;

static void kill_uml(const char *reason)
{
    fprintf(stderr, "uml_watchdog: %s — killing UML (pid %d)\n",
            reason, watched_pid);
    if (watched_pid > 0)
        kill(watched_pid, SIGKILL);
    exit(1);
}

/* Mode: -pid <pid> — simple pipe-based watchdog */
static int mode_pid(pid_t pid)
{
    struct timeval tv;
    fd_set rfds;
    char buf[1];
    ssize_t n;

    watched_pid = pid;

    while (1) {
        FD_ZERO(&rfds);
        FD_SET(PING_FD, &rfds);
        tv.tv_sec  = WATCHDOG_TIMEOUT;
        tv.tv_usec = 0;

        int ret = select(PING_FD + 1, &rfds, NULL, NULL, &tv);
        if (ret < 0) {
            if (errno == EINTR) continue;
            kill_uml("select error");
        }
        if (ret == 0)
            kill_uml("timeout — UML hung");

        n = read(PING_FD, buf, 1);
        if (n <= 0)
            kill_uml("kernel pipe closed");

        /* Ack the ping */
        write(ACK_FD, buf, 1);
    }
    return 0;
}

/* Mode: -mconsole <socket> — mconsole-based watchdog */
static int mode_mconsole(const char *sock_path)
{
    int sock;
    struct sockaddr_un addr;
    struct timeval tv;
    fd_set rfds;
    char buf[256];
    ssize_t n;

    sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("uml_watchdog: socket");
        return 1;
    }

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);

    /* Wait for mconsole socket to appear */
    int tries = 30;
    while (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        if (--tries <= 0) {
            fprintf(stderr, "uml_watchdog: cannot connect to %s\n", sock_path);
            return 1;
        }
        sleep(1);
    }

    while (1) {
        FD_ZERO(&rfds);
        FD_SET(sock, &rfds);
        FD_SET(PING_FD, &rfds);
        tv.tv_sec  = WATCHDOG_TIMEOUT;
        tv.tv_usec = 0;

        int maxfd = sock > PING_FD ? sock : PING_FD;
        int ret = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        if (ret < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (ret == 0)
            kill_uml("mconsole timeout — UML hung");

        if (FD_ISSET(PING_FD, &rfds)) {
            n = read(PING_FD, buf, 1);
            if (n <= 0) break;
            write(ACK_FD, buf, 1);
        }
        if (FD_ISSET(sock, &rfds)) {
            n = read(sock, buf, sizeof(buf));
            if (n <= 0) break;
        }
    }
    close(sock);
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc < 2) {
        fprintf(stderr, "Usage: uml_watchdog -pid <pid> | -mconsole <socket>\n");
        return 1;
    }

    signal(SIGPIPE, SIG_IGN);

    if (strcmp(argv[1], "-pid") == 0 && argc >= 3)
        return mode_pid((pid_t)atoi(argv[2]));

    if (strcmp(argv[1], "-mconsole") == 0 && argc >= 3)
        return mode_mconsole(argv[2]);

    fprintf(stderr, "uml_watchdog: unknown mode: %s\n", argv[1]);
    return 1;
}
