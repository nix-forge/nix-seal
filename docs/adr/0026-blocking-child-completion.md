# ADR 0026: Blocking child completion

Status: accepted

Service-manager actions, external generators, migration helpers, and deployment
preparation previously checked child exit every 10 to 25 milliseconds. These
checks woke an otherwise idle process throughout a helper's execution.

The runtime provides one shared subprocess owner. Its observer thread blocks in
`waitid(WEXITED | WNOWAIT)` using the existing rustix dependency. Callers wait on a
condition variable until completion or their existing absolute deadline. The
observer reaps the child under the same mutex used for cancellation. Until then,
the unreaped child reserves its PID, including if cancellation runs before the
observer starts. This avoids signalling a recycled process-group ID. Interrupts
restart the blocking wait; no global SIGCHLD handler is installed.

Cancellation retains direct-child termination for service-manager actions and
deployment preparation. External generators and migration helpers retain their
private process groups and group termination while the leader runs. Dropping
the owner cancels unfinished work and joins the observer, including error paths.
Migration's existing watchdog can cancel while another thread waits for exit.

Linux and Darwin use the same safe rustix wait interface. Each active supervised
child adds one sleeping observer thread. This bounded thread cost replaces the
repeated process-status wakeups without a new dependency or platform-specific
signal handler. Deadline and output limits, executable authorization, sandbox
setup, secret handling, and publication rules do not change. No trust boundary
moves, so the existing threat model remains applicable.
