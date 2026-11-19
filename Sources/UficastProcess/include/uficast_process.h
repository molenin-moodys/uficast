#ifndef UFICAST_PROCESS_H
#define UFICAST_PROCESS_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct UFProcess UFProcess;
enum { UF_PROCESS_EXITED = 0, UF_PROCESS_TIMED_OUT = 1, UF_PROCESS_CANCELLED = 2 };
UFProcess *uf_process_create(void);
void uf_process_destroy(UFProcess *process);
/* The only concurrent operation; requests cancellation through an atomic flag. */
void uf_process_cancel(UFProcess *process);
/* Blocking worker API. Other accessors are used only after it returns. */
int uf_process_run(UFProcess *process, const char *executable, char *const argv[],
                   char *const environment[], const char *directory, double timeout, size_t limit);
const uint8_t *uf_process_stdout(const UFProcess *process);
const uint8_t *uf_process_stderr(const UFProcess *process);
size_t uf_process_stdout_size(const UFProcess *process);
size_t uf_process_stderr_size(const UFProcess *process);
bool uf_process_stdout_truncated(const UFProcess *process);
bool uf_process_stderr_truncated(const UFProcess *process);
int uf_process_exit_code(const UFProcess *process);
int uf_process_reason(const UFProcess *process);
#endif
