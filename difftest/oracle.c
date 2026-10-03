// Talks to the Rust oracle process (see difftest/oracle) over pipes.
#include <moonbit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <poll.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static FILE *oracle_in = NULL;
static FILE *oracle_out = NULL;
static pid_t oracle_pid = 0;

MOONBIT_FFI_EXPORT int difftest_oracle_start(moonbit_bytes_t path) {
  // restarting: drop the pipes of the previous (dead) oracle
  if (oracle_in != NULL) {
    if (oracle_pid > 0) {
      kill(oracle_pid, SIGKILL);
      waitpid(oracle_pid, NULL, 0);
    }
    fclose(oracle_in);
    fclose(oracle_out);
    oracle_in = NULL;
    oracle_out = NULL;
  }
  int to_child[2], from_child[2];
  if (pipe(to_child) != 0 || pipe(from_child) != 0) {
    return -1;
  }
  pid_t pid = fork();
  if (pid < 0) {
    return -1;
  }
  if (pid == 0) {
    dup2(to_child[0], 0);
    dup2(from_child[1], 1);
    close(to_child[1]);
    close(from_child[0]);
    execl((const char *)path, (const char *)path, (char *)NULL);
    _exit(127);
  }
  oracle_pid = pid;
  close(to_child[0]);
  close(from_child[1]);
  oracle_in = fdopen(to_child[1], "w");
  oracle_out = fdopen(from_child[0], "r");
  return 0;
}

// Sends one line and returns the response line: empty if the oracle died,
// "TIMEOUT" if it did not answer within `timeout_ms`.
MOONBIT_FFI_EXPORT moonbit_bytes_t difftest_oracle_query(moonbit_bytes_t req,
                                                        int timeout_ms) {
  size_t n = Moonbit_array_length(req);
  fwrite(req, 1, n, oracle_in);
  fputc('\n', oracle_in);
  fflush(oracle_in);
  // responses are single lines, so nothing is left buffered between calls
  struct pollfd p = {fileno(oracle_out), POLLIN, 0};
  if (poll(&p, 1, timeout_ms) <= 0) {
    static const char msg[] = "TIMEOUT";
    moonbit_bytes_t rv = moonbit_make_bytes(sizeof(msg) - 1, 0);
    memcpy(rv, msg, sizeof(msg) - 1);
    return rv;
  }
  char *line = NULL;
  size_t cap = 0;
  ssize_t len = getline(&line, &cap, oracle_out);
  if (len < 0) {
    free(line);
    return moonbit_make_bytes(0, 0);
  }
  if (len > 0 && line[len - 1] == '\n') {
    len--;
  }
  moonbit_bytes_t rv = moonbit_make_bytes(len, 0);
  memcpy(rv, line, len);
  free(line);
  return rv;
}

// Writes `data` to `path` (used to keep the last case around if we crash).
MOONBIT_FFI_EXPORT void difftest_write_file(moonbit_bytes_t path,
                                            moonbit_bytes_t data) {
  FILE *f = fopen((const char *)path, "wb");
  if (f == NULL) {
    return;
  }
  fwrite(data, 1, Moonbit_array_length(data), f);
  fclose(f);
}

// Arms (or with 0 disarms) a watchdog that terminates the process if our
// own engine hangs; the last case file then names the culprit.
MOONBIT_FFI_EXPORT void difftest_alarm(int seconds) { alarm(seconds); }
