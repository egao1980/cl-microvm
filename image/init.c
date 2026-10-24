/* PID 1 for the cl-microvm guest. Mounts the pseudo-filesystems SBCL needs,
   then runs one child as uid 65534. */
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static pid_t child_pid;

static void on_signal(int sig) {
    if (child_pid > 0)
        kill(child_pid, sig);
}

static void mount_fs(const char *source, const char *target, const char *fstype,
                     unsigned long flags, mode_t mode) {
    if (mkdir(target, mode) != 0 && errno != EEXIST)
        fprintf(stderr, "mkdir %s: %s\n", target, strerror(errno));
    if (mount(source, target, fstype, flags, NULL) != 0 &&
        errno != EBUSY && errno != EPERM)
        fprintf(stderr, "mount %s: %s\n", target, strerror(errno));
    chmod(target, mode);
}

static void load_env_file(const char *path) {
    FILE *in = fopen(path, "r");
    char line[512];

    if (!in)
        return;
    while (fgets(line, sizeof line, in)) {
        char *nl = strchr(line, '\n');
        char *eq;
        if (nl)
            *nl = 0;
        if (line[0] == '\0' || line[0] == '#')
            continue;
        eq = strchr(line, '=');
        if (!eq || eq == line)
            continue;
        *eq = 0;
        setenv(line, eq + 1, 1);
    }
    fclose(in);
}

static void write_resolv_from_pnp(void) {
    FILE *in = fopen("/proc/net/pnp", "r");
    FILE *out = NULL;
    char line[512];

    if (!in)
        return;
    while (fgets(line, sizeof line, in)) {
        if (strncmp(line, "nameserver ", 11) != 0)
            continue;
        if (!out) {
            out = fopen("/etc/resolv.conf", "w");
            if (!out)
                break;
        }
        fputs(line, out);
    }
    if (out)
        fclose(out);
    fclose(in);
}

static void drop_privs(void) {
    if (geteuid() != 0)
        return;
    if (setgid(65534) != 0)
        perror("setgid");
    if (setuid(65534) != 0)
        perror("setuid");
}

static void exec_child(int argc, char **argv) {
    if (argc > 1 && argv[1][0] == '/') {
        execv(argv[1], &argv[1]);
        perror(argv[1]);
        _exit(127);
    }

    char *sbcl[64];
    int n = 0;
    sbcl[n++] = "/usr/local/bin/sbcl";
    sbcl[n++] = "--disable-debugger";
    sbcl[n++] = "--non-interactive";
    if (argc > 1) {
        for (int i = 1; i < argc && n < 62; i++)
            sbcl[n++] = argv[i];
    } else {
        sbcl[n++] = "--load";
        sbcl[n++] = "/opt/cl-microvm/boot.lisp";
    }
    sbcl[n] = NULL;
    execv(sbcl[0], sbcl);
    perror(sbcl[0]);
    _exit(127);
}

int main(int argc, char **argv) {
    mount_fs("proc", "/proc", "proc", 0, 0555);
    mount_fs("sysfs", "/sys", "sysfs", 0, 0555);
    mount_fs("devtmpfs", "/dev", "devtmpfs", 0, 0755);
    mount_fs("tmpfs", "/dev/shm", "tmpfs", 0, 01777);
    mount_fs("tmpfs", "/tmp", "tmpfs", 0, 01777);
    mount_fs("tmpfs", "/run", "tmpfs", 0, 0755);
    if (mount(NULL, "/", NULL, MS_REMOUNT, NULL) != 0 &&
        errno != EBUSY && errno != EINVAL && errno != EPERM)
        fprintf(stderr, "remount /: %s\n", strerror(errno));

    write_resolv_from_pnp();
    setenv("SBCL_HOME", "/usr/local/lib/sbcl", 0);
    setenv("HOME", "/data", 0);
    setenv("XDG_CACHE_HOME", "/opt/cache", 0);
    setenv("PATH", "/usr/local/bin:/usr/bin:/bin", 1);
    load_env_file("/etc/cl-microvm.env");

    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);

    child_pid = fork();
    if (child_pid < 0) {
        perror("fork");
        return 1;
    }
    if (child_pid == 0) {
        drop_privs();
        exec_child(argc, argv);
    }

    for (;;) {
        int status = 0;
        pid_t got = wait(&status);
        if (got == child_pid) {
            if (WIFEXITED(status))
                return WEXITSTATUS(status);
            if (WIFSIGNALED(status))
                return 128 + WTERMSIG(status);
            return 1;
        }
        if (got < 0 && errno != EINTR)
            return 1;
    }
}
