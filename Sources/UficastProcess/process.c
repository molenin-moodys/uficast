#include "uficast_process.h"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

struct Capture { uint8_t *data; size_t size; bool truncated; };
struct UFProcess {
    atomic_bool cancelled;
    struct Capture out, err;
    int exit_code, reason;
};

UFProcess *uf_process_create(void) {
    UFProcess *process = calloc(1, sizeof(UFProcess));
    if (process) { atomic_init(&process->cancelled, false); process->exit_code = -1; }
    return process;
}
void uf_process_destroy(UFProcess *process) {
    if (!process) return;
    free(process->out.data); free(process->err.data); free(process);
}
void uf_process_cancel(UFProcess *process) { atomic_store(&process->cancelled, true); }
const uint8_t *uf_process_stdout(const UFProcess *p) { return p->out.data; }
const uint8_t *uf_process_stderr(const UFProcess *p) { return p->err.data; }
size_t uf_process_stdout_size(const UFProcess *p) { return p->out.size; }
size_t uf_process_stderr_size(const UFProcess *p) { return p->err.size; }
bool uf_process_stdout_truncated(const UFProcess *p) { return p->out.truncated; }
bool uf_process_stderr_truncated(const UFProcess *p) { return p->err.truncated; }
int uf_process_exit_code(const UFProcess *p) { return p->exit_code; }
int uf_process_reason(const UFProcess *p) { return p->reason; }

static double now(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
static void close_fd(int *fd) { if (*fd >= 0) { close(*fd); *fd = -1; } }
static int create_pipe(int descriptors[2]) {
    if (pipe(descriptors)) return -1;
    /* The caller can have closed stdin/stdout. Keep spawn actions disjoint. */
    for (int i = 0; i < 2; ++i) if (descriptors[i] <= STDERR_FILENO) {
        int duplicate = fcntl(descriptors[i], F_DUPFD_CLOEXEC, STDERR_FILENO + 1);
        if (duplicate < 0) return -1;
        close(descriptors[i]); descriptors[i] = duplicate;
    }
    return 0;
}

static int drain(int *fd, struct Capture *capture, size_t limit) {
    uint8_t buffer[16384];
    /* Bound work per poll iteration so a busy writer cannot starve deadlines. */
    for (int iteration = 0; iteration < 64 && *fd >= 0; ++iteration) {
        ssize_t count = read(*fd, buffer, sizeof(buffer));
        if (count > 0) {
            size_t available = limit - capture->size;
            size_t keep = (size_t)count < available ? (size_t)count : available;
            if (keep) memcpy(capture->data + capture->size, buffer, keep);
            capture->size += keep;
            if (keep < (size_t)count) capture->truncated = true;
        } else if (count == 0) { close_fd(fd); }
        else if (errno == EAGAIN || errno == EWOULDBLOCK) return 0;
        else if (errno != EINTR) { int error = errno; close_fd(fd); return error; }
    }
    return 0;
}

/* Writes the next bounded chunk of stdin; closes the pipe when done or when the
   child stops reading (EPIPE). F_SETNOSIGPIPE turns SIGPIPE into that error. */
static void feed(int *fd, const uint8_t *input, size_t size, size_t *written) {
    for (int iteration = 0; iteration < 4 && *fd >= 0; ++iteration) {
        if (*written >= size) { close_fd(fd); return; }
        size_t chunk = size - *written < 16384 ? size - *written : 16384;
        ssize_t count = write(*fd, input + *written, chunk);
        if (count > 0) *written += (size_t)count;
        else if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
        else if (count < 0 && errno == EINTR) continue;
        else { close_fd(fd); return; }
    }
    if (*fd >= 0 && *written >= size) close_fd(fd);
}

int uf_process_run(UFProcess *p, const char *executable, char *const argv[],
                   char *const environment[], const char *directory, double timeout, size_t limit) {
    return uf_process_run_input(p, executable, argv, environment, directory, timeout, limit, NULL, 0);
}

int uf_process_run_input(UFProcess *p, const char *executable, char *const argv[],
                         char *const environment[], const char *directory, double timeout, size_t limit,
                         const uint8_t *input, size_t input_size) {
    int out[2] = {-1, -1}, err[2] = {-1, -1}, in[2] = {-1, -1};
    size_t written = 0;
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    int error = 0;
    pid_t pid = -1;
    bool owns_leader = true;
    if (atomic_load(&p->cancelled)) { p->reason = UF_PROCESS_CANCELLED; return 0; }
    p->out.data = malloc(limit); p->err.data = malloc(limit);
    if (!p->out.data || !p->err.data) return ENOMEM;
    if (create_pipe(out) || create_pipe(err) || (input && create_pipe(in))) { error = errno; goto close_pipes; }
    if ((error = posix_spawn_file_actions_init(&actions))) goto close_pipes;
    if ((error = posix_spawnattr_init(&attributes))) goto destroy_actions;

    #define CHECK(call) do { error = (call); if (error) goto destroy_attributes; } while (0)
    if (input) {
        CHECK(posix_spawn_file_actions_adddup2(&actions, in[0], STDIN_FILENO));
        CHECK(posix_spawn_file_actions_addclose(&actions, in[0]));
        CHECK(posix_spawn_file_actions_addclose(&actions, in[1]));
    } else {
        CHECK(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0));
    }
    CHECK(posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO));
    CHECK(posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO));
    CHECK(posix_spawn_file_actions_addclose(&actions, out[0]));
    CHECK(posix_spawn_file_actions_addclose(&actions, err[0]));
    CHECK(posix_spawn_file_actions_addclose(&actions, out[1]));
    CHECK(posix_spawn_file_actions_addclose(&actions, err[1]));
    CHECK(posix_spawn_file_actions_addchdir(&actions, directory));
    CHECK(posix_spawnattr_setpgroup(&attributes, 0));
    sigset_t empty, defaults;
    sigemptyset(&empty); sigemptyset(&defaults);
    sigaddset(&defaults, SIGPIPE); sigaddset(&defaults, SIGTERM);
    sigaddset(&defaults, SIGINT); sigaddset(&defaults, SIGHUP); sigaddset(&defaults, SIGQUIT);
    CHECK(posix_spawnattr_setsigmask(&attributes, &empty));
    CHECK(posix_spawnattr_setsigdefault(&attributes, &defaults));
    CHECK(posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                   | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF));
    CHECK(posix_spawn(&pid, executable, &actions, &attributes, argv, environment));
    #undef CHECK

destroy_attributes:
    posix_spawnattr_destroy(&attributes);
destroy_actions:
    posix_spawn_file_actions_destroy(&actions);
    if (error) goto close_pipes;
    close_fd(&out[1]); close_fd(&err[1]); close_fd(&in[0]);
    if (fcntl(out[0], F_SETFL, O_NONBLOCK) < 0 || fcntl(err[0], F_SETFL, O_NONBLOCK) < 0
        || (in[1] >= 0 && (fcntl(in[1], F_SETFL, O_NONBLOCK) < 0 || fcntl(in[1], F_SETNOSIGPIPE, 1) < 0))) {
        error = errno; kill(-pid, SIGKILL); goto reap;
    }
    if (in[1] >= 0 && input_size == 0) close_fd(&in[1]);
    double deadline = now() + timeout, stopped_at = 0;
    bool exited = false, sent_kill = false;
    while (!exited || out[0] >= 0 || err[0] >= 0) {
        double current = now();
        if (!stopped_at && (atomic_load(&p->cancelled) || current >= deadline || error)) {
            p->reason = atomic_load(&p->cancelled) ? UF_PROCESS_CANCELLED : UF_PROCESS_TIMED_OUT;
            stopped_at = current;
            close_fd(&in[1]);
            kill(-pid, SIGTERM);
        }
        if (stopped_at && !sent_kill && current - stopped_at >= 0.2) {
            kill(-pid, SIGKILL); sent_kill = true;
        }
        if (stopped_at && current - stopped_at >= 1.0) {
            /* A deliberately detached process can keep a pipe open. Bound draining. */
            if (out[0] >= 0) p->out.truncated = true;
            if (err[0] >= 0) p->err.truncated = true;
            close_fd(&out[0]); close_fd(&err[0]);
        }
        /* A negative descriptor is ignored by poll, so a finished stdin costs nothing. */
        struct pollfd fds[3] = {{out[0], POLLIN, 0}, {err[0], POLLIN, 0}, {in[1], POLLOUT, 0}};
        int ready = poll(fds, 3, 25);
        if (ready < 0 && errno != EINTR) { error = errno; }
        if (fds[0].revents) { int result = drain(&out[0], &p->out, limit); if (result) error = result; }
        if (fds[1].revents) { int result = drain(&err[0], &p->err, limit); if (result) error = result; }
        if (fds[2].revents) feed(&in[1], input, input_size, &written);
        if (exited) close_fd(&in[1]);
        if (!exited) {
            siginfo_t info = {0};
            /* Hold the leader as a zombie until pipes close. Its PID cannot be
               reused while a deadline may still signal our process group. */
            if (waitid(P_PID, (id_t)pid, &info, WEXITED | WNOWAIT | WNOHANG) == 0) exited = info.si_pid == pid;
            else if (errno != EINTR) { error = errno; owns_leader = errno != ECHILD; break; }
        }
    }
    /* A shell may exit while a child closes its streams but keeps running.
       Clean the managed group before releasing the reserved leader PID. */
    if (!owns_leader) goto close_pipes;
    kill(-pid, SIGKILL);
reap: {
        int status;
        while (waitpid(pid, &status, 0) < 0) { if (errno != EINTR) { error = errno; goto close_pipes; } }
        p->exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
    }
close_pipes:
    close_fd(&out[0]); close_fd(&out[1]); close_fd(&err[0]); close_fd(&err[1]);
    close_fd(&in[0]); close_fd(&in[1]);
    return error;
}
