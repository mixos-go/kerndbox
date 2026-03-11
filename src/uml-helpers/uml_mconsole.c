/*
 * uml_mconsole — UML management console client
 *
 * Connects to the mconsole Unix socket of a running UML instance and
 * sends management commands. The mconsole driver inside the kernel
 * listens on ~/.uml/<umid>/mconsole.
 *
 * Usage:
 *   uml_mconsole <umid> [command [args...]]
 *   uml_mconsole <socket-path> [command [args...]]
 *
 * Commands:
 *   version      — print kernel version
 *   halt         — halt the UML instance
 *   reboot       — reboot the UML instance
 *   config <dev>=<config>  — reconfigure a device
 *   remove <dev> — remove a device
 *   cad          — Ctrl-Alt-Del
 *   stop         — stop all threads (for debugging)
 *   go           — resume after stop
 *   log <msg>    — write message to kernel log
 *   proc <file>  — read /proc/<file>
 *   stack        — print thread stacks
 *   sysrq <key>  — send SysRq key
 *
 * Protocol: see Linux kernel arch/um/drivers/mconsole_kern.c
 *   Request:  struct mconsole_request  { magic, id, len, data[] }
 *   Reply:    struct mconsole_reply    { magic, err, more, len, data[] }
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <pwd.h>

/* From linux/um_timetravel.h — mconsole magic */
#define MCONSOLE_MAGIC      0xcafebabe
#define MCONSOLE_MAX_DATA   512

struct mconsole_request {
    unsigned int  magic;
    unsigned int  id;
    unsigned short len;
    char          data[MCONSOLE_MAX_DATA];
};

struct mconsole_reply {
    unsigned int  magic;
    int           err;
    int           more;
    unsigned short len;
    char          data[MCONSOLE_MAX_DATA];
};

static char *find_socket(const char *umid)
{
    static char path[512];
    struct stat st;
    const char *home;

    /* Direct path? */
    if (umid[0] == '/') {
        snprintf(path, sizeof(path), "%s", umid);
        if (stat(path, &st) == 0) return path;
    }

    /* ~/.uml/<umid>/mconsole */
    home = getenv("HOME");
    if (!home) {
        struct passwd *pw = getpwuid(getuid());
        home = pw ? pw->pw_dir : "/tmp";
    }
    snprintf(path, sizeof(path), "%s/.uml/%s/mconsole", home, umid);
    if (stat(path, &st) == 0) return path;

    /* /tmp/uml-<umid>/mconsole (kerndbox convention) */
    snprintf(path, sizeof(path), "/tmp/uml-%s/mconsole", umid);
    if (stat(path, &st) == 0) return path;

    return NULL;
}

static int send_command(const char *sock_path, const char *cmd)
{
    int sock;
    struct sockaddr_un addr, my_addr;
    struct mconsole_request req;
    struct mconsole_reply reply;
    char tmp_path[64];
    ssize_t n;

    sock = socket(AF_UNIX, SOCK_DGRAM, 0);
    if (sock < 0) { perror("socket"); return 1; }

    /* Bind to a temp socket so kernel can reply */
    snprintf(tmp_path, sizeof(tmp_path), "/tmp/uml_mc_%d", getpid());
    unlink(tmp_path);
    memset(&my_addr, 0, sizeof(my_addr));
    my_addr.sun_family = AF_UNIX;
    strncpy(my_addr.sun_path, tmp_path, sizeof(my_addr.sun_path)-1);
    bind(sock, (struct sockaddr *)&my_addr, sizeof(my_addr));

    /* Build request */
    memset(&req, 0, sizeof(req));
    req.magic = MCONSOLE_MAGIC;
    req.id    = (unsigned)getpid();
    req.len   = strlen(cmd) < MCONSOLE_MAX_DATA ? strlen(cmd) : MCONSOLE_MAX_DATA-1;
    memcpy(req.data, cmd, req.len);

    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path)-1);

    if (sendto(sock, &req, sizeof(req), 0,
               (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("sendto");
        unlink(tmp_path);
        return 1;
    }

    /* Read replies (more=1 means more data coming) */
    do {
        n = recv(sock, &reply, sizeof(reply), 0);
        if (n < 0) { perror("recv"); break; }
        if (reply.len > 0)
            fwrite(reply.data, 1, reply.len, stdout);
    } while (reply.more);

    if (reply.err)
        fprintf(stderr, "mconsole error: %d\n", reply.err);

    unlink(tmp_path);
    close(sock);
    return reply.err ? 1 : 0;
}

int main(int argc, char *argv[])
{
    char cmd[MCONSOLE_MAX_DATA];
    char *sock_path;
    int i;

    if (argc < 2) {
        fprintf(stderr,
            "Usage: uml_mconsole <umid|socket> [command [args...]]\n"
            "       uml_mconsole <umid|socket>  (interactive)\n"
            "\nCommands: version halt reboot config remove cad stop go log proc stack sysrq\n");
        return 1;
    }

    sock_path = find_socket(argv[1]);
    if (!sock_path) {
        fprintf(stderr, "uml_mconsole: cannot find mconsole socket for '%s'\n", argv[1]);
        fprintf(stderr, "  Tried: ~/.uml/%s/mconsole, /tmp/uml-%s/mconsole\n",
                argv[1], argv[1]);
        return 1;
    }

    if (argc >= 3) {
        /* Single command from arguments */
        cmd[0] = '\0';
        for (i = 2; i < argc; i++) {
            if (i > 2) strncat(cmd, " ", sizeof(cmd)-1);
            strncat(cmd, argv[i], sizeof(cmd)-1);
        }
        return send_command(sock_path, cmd);
    }

    /* Interactive mode */
    fprintf(stderr, "Connected to %s\n", sock_path);
    while (fgets(cmd, sizeof(cmd), stdin)) {
        cmd[strcspn(cmd, "\n")] = '\0';
        if (!cmd[0]) continue;
        if (strcmp(cmd, "quit") == 0 || strcmp(cmd, "exit") == 0) break;
        send_command(sock_path, cmd);
        putchar('\n');
    }
    return 0;
}
