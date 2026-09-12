//! Blocking subprocess completion with bounded waits and serialized cancellation.

use rustix::process::{Pid, Signal, WaitId, WaitIdOptions, kill_process_group, waitid};
use std::{
    io,
    process::{Child, ExitStatus},
    sync::{Arc, Condvar, Mutex, MutexGuard},
    thread::{self, JoinHandle},
    time::Instant,
};

/// Which processes cancellation may terminate.
#[derive(Clone, Copy)]
pub enum ChildTermination {
    /// Terminate only the owned child.
    Process,
    /// Terminate the child's private process group.
    ///
    /// The caller must have spawned the child with `Command::process_group(0)`.
    ProcessGroup,
}

struct State {
    child: Child,
    result: Option<io::Result<ExitStatus>>,
}

struct Shared {
    state: Mutex<State>,
    completed: Condvar,
    termination: ChildTermination,
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    fn terminate(&self, state: &mut State) {
        if state.result.is_some() {
            return;
        }
        let Some(pid) = Pid::from_raw(state.child.id().cast_signed()) else {
            return;
        };
        // Never reap here: the observer may not have started yet. Only a
        // waitable, still-running child authorizes signalling. ECHILD means
        // ownership was lost, so its numeric PID must no longer be used.
        let running = loop {
            match waitid(
                WaitId::Pid(pid),
                WaitIdOptions::EXITED | WaitIdOptions::NOWAIT | WaitIdOptions::NOHANG,
            ) {
                Err(rustix::io::Errno::INTR) => {}
                result => break matches!(result, Ok(None)),
            }
        };
        if running {
            if let ChildTermination::ProcessGroup = self.termination {
                let _ = kill_process_group(pid, Signal::KILL);
            }
            let _ = state.child.kill();
        }
    }
}

/// Owns a child until it is reaped, including during concurrent cancellation.
///
/// One worker blocks in `waitid(WEXITED | WNOWAIT)`. Reaping and cancellation
/// share a mutex, so the child's PID cannot be recycled between checking its
/// state and signalling its process group. Deadline waits use a condition
/// variable and install no process-wide signal handlers. Drop cancels unfinished
/// work and joins the observer.
pub struct SupervisedChild {
    shared: Arc<Shared>,
    observer: Option<JoinHandle<()>>,
}

impl SupervisedChild {
    /// Takes ownership after the caller has extracted any stdin/stdout pipes.
    pub fn new(mut child: Child, termination: ChildTermination) -> io::Result<Self> {
        // Honor std's cached exit status before reading the PID. This also
        // avoids an observer thread for children that have already finished.
        let result = child.try_wait()?.map(Ok);
        let shared = Arc::new(Shared {
            state: Mutex::new(State { child, result }),
            completed: Condvar::new(),
            termination,
        });
        if shared.lock().result.is_some() {
            return Ok(Self {
                shared,
                observer: None,
            });
        }
        let observer_shared = Arc::clone(&shared);
        let observer = thread::Builder::new()
            .name("nix-seal-child".into())
            .spawn(move || {
                let pid = Pid::from_raw(observer_shared.lock().child.id().cast_signed());
                let observed = pid
                    .ok_or_else(|| io::Error::other("invalid child PID"))
                    .and_then(|pid| {
                        loop {
                            match waitid(
                                WaitId::Pid(pid),
                                WaitIdOptions::EXITED | WaitIdOptions::NOWAIT,
                            ) {
                                Err(rustix::io::Errno::INTR) => {}
                                Ok(Some(_)) => break Ok(()),
                                Ok(None) => {
                                    break Err(io::Error::other("child exit was not reported"));
                                }
                                Err(error) => break Err(error.into()),
                            }
                        }
                    });
                let mut state = observer_shared.lock();
                if observed.is_err() {
                    observer_shared.terminate(&mut state);
                }
                let status = state.child.wait();
                state.result = Some(observed.and(status));
                observer_shared.completed.notify_all();
            });
        match observer {
            Ok(observer) => Ok(Self {
                shared,
                observer: Some(observer),
            }),
            Err(error) => {
                let mut state = shared.lock();
                shared.terminate(&mut state);
                let _ = state.child.wait();
                Err(error)
            }
        }
    }

    /// Waits until exit or an absolute deadline. A timeout leaves cancellation
    /// to the caller; dropping this owner also cancels unfinished work.
    pub fn wait_until(&self, deadline: Instant) -> io::Result<Option<ExitStatus>> {
        let mut state = self.shared.lock();
        loop {
            if let Some(result) = &state.result {
                return result
                    .as_ref()
                    .map(|status| Some(*status))
                    .map_err(|error| {
                        error.raw_os_error().map_or_else(
                            || io::Error::new(error.kind(), error.to_string()),
                            io::Error::from_raw_os_error,
                        )
                    });
            }
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Ok(None);
            }
            (state, _) = self
                .shared
                .completed
                .wait_timeout(state, remaining)
                .unwrap_or_else(std::sync::PoisonError::into_inner);
        }
    }

    /// Signals unfinished work. Safe to call concurrently with a deadline wait
    /// or repeatedly after completion. Drop joins the reaping worker.
    pub fn terminate(&self) {
        self.shared.terminate(&mut self.shared.lock());
    }
}

impl Drop for SupervisedChild {
    fn drop(&mut self) {
        self.terminate();
        if let Some(observer) = self.observer.take() {
            let _ = observer.join();
        }
    }
}
