/*
 * port-helper — UML console bridge helper
 *
 * Called in two modes by the UML kernel:
 *
 *   Mode 1 (port channel, via in.telnetd -L):
 *     Kernel forks, child inherits socket fd (from accept()), execs:
 *       in.telnetd -L port-helper
 *     in.telnetd calls port-helper as login replacement with:
 *       stdin/stdout = telnet connection to user
 *     We bridge stdin/stdout ↔ the kernel's pipe socket pair.
 *     The kernel pipe fds are passed via environment: UML_PORT_HELPER_FD=<fd>
 *
 *   Mode 2 (xterm channel):
 *     Kernel execs: xterm -T title -e port-helper -uml-socket <path>
 *     We connect to the Unix domain socket at <path> and bridge
 *     stdin/stdout ↔ socket, giving the user a terminal window.
 *
 * Must be statically linked so it can be embedded in the kernel ELF and
 * extracted to /tmp at runtime without requiring a dynamic linker.
 *
 * Interface derived from Linux kernel 6.x:
 *   arch/um/drivers/port_user.c
 *   arch/um/drivers/xterm.c
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/types.h>
#include <sys/stat.h>

#define BUFSIZE 4096

static void bridge(int fd_a, int fd_b)
{
	char buf[BUFSIZE];
	fd_set rfds;
	int maxfd = (fd_a > fd_b ? fd_a : fd_b) + 1;
	ssize_t n;

	while (1) {
		FD_ZERO(&rfds);
		FD_SET(fd_a, &rfds);
		FD_SET(fd_b, &rfds);

		if (select(maxfd, &rfds, NULL, NULL, NULL) < 0) {
			if (errno == EINTR)
				continue;
			break;
		}

		if (FD_ISSET(fd_a, &rfds)) {
			n = read(fd_a, buf, sizeof(buf));
			if (n <= 0) break;
			if (write(fd_b, buf, n) != n) break;
		}
		if (FD_ISSET(fd_b, &rfds)) {
			n = read(fd_b, buf, sizeof(buf));
			if (n <= 0) break;
			if (write(fd_a, buf, n) != n) break;
		}
	}
}

/* Mode 2: xterm channel — connect to Unix socket, bridge to terminal */
static int mode_xterm(const char *sock_path)
{
	int sock;
	struct sockaddr_un addr;

	sock = socket(AF_UNIX, SOCK_STREAM, 0);
	if (sock < 0) {
		perror("port-helper: socket");
		return 1;
	}

	memset(&addr, 0, sizeof(addr));
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);

	if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		perror("port-helper: connect");
		return 1;
	}

	/* Detach from controlling terminal */
	setsid();

	/* Bridge: terminal (stdin=0, stdout=1) ↔ kernel unix socket */
	bridge(0, sock);
	close(sock);
	return 0;
}

/* Mode 1: port channel — bridge the fd pair passed by kernel via env var
 * The kernel's port_user.c sets up a socketpair and passes one end to us.
 * In.telnetd calls us with its connection on stdin/stdout.
 */
static int mode_port(void)
{
	const char *fd_env;
	int kern_fd;

	fd_env = getenv("UML_PORT_HELPER_FD");
	if (!fd_env) {
		/*
		 * Older kernels don't set UML_PORT_HELPER_FD.
		 * Fall back: bridge fd 3 (first non-std fd, typically the
		 * socket from kernel's socketpair that was inherited).
		 */
		kern_fd = 3;
	} else {
		kern_fd = atoi(fd_env);
	}

	/* Detach from any controlling terminal */
	setsid();

	/* Bridge: telnet connection (stdin=0/stdout=1) ↔ kernel socket */
	bridge(0, kern_fd);
	return 0;
}

int main(int argc, char *argv[])
{
	/* Ignore SIGPIPE — we handle EOF in bridge() loop */
	signal(SIGPIPE, SIG_IGN);

	if (argc >= 3 && strcmp(argv[1], "-uml-socket") == 0)
		return mode_xterm(argv[2]);

	return mode_port();
}
