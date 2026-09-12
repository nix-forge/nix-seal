//! Native Linux and Darwin checks for child exit, deadlines, and cancellation.

use nix_seal_runtime::child::{ChildTermination, SupervisedChild};
use std::{
    io::{BufRead, BufReader, Read},
    os::unix::process::CommandExt,
    process::{Command, Stdio},
    sync::{Arc, mpsc},
    thread,
    time::{Duration, Instant},
};

type TestResult = Result<(), Box<dyn std::error::Error>>;

fn deadline() -> Instant {
    Instant::now() + Duration::from_secs(5)
}

#[test]
fn reports_success_failure_and_cached_status() -> TestResult {
    for code in [0, 7] {
        let child = Command::new("sh")
            .args(["-c", &format!("exit {code}")])
            .spawn()?;
        let child = SupervisedChild::new(child, ChildTermination::Process)?;
        let status = child.wait_until(deadline())?.ok_or("child did not exit")?;
        assert_eq!(status.code(), Some(code));
        child.terminate();
        assert_eq!(child.wait_until(Instant::now())?, Some(status));
    }
    Ok(())
}

#[test]
fn observes_child_that_exited_before_registration() -> TestResult {
    use rustix::process::{Pid, WaitId, WaitIdOptions, waitid};
    let child = Command::new("sh").args(["-c", "exit 9"]).spawn()?;
    let pid = Pid::from_raw(child.id().cast_signed()).ok_or("invalid PID")?;
    waitid(
        WaitId::Pid(pid),
        WaitIdOptions::EXITED | WaitIdOptions::NOWAIT,
    )?;
    let child = SupervisedChild::new(child, ChildTermination::Process)?;
    assert_eq!(
        child
            .wait_until(deadline())?
            .and_then(|status| status.code()),
        Some(9)
    );
    Ok(())
}

#[test]
fn deadline_still_applies_after_output_closes() -> TestResult {
    let mut child = Command::new("sh")
        .args(["-c", "exec 1>&-; exec sleep 30"])
        .stdout(Stdio::piped())
        .spawn()?;
    let mut stdout = child.stdout.take().ok_or("missing stdout")?;
    let child = SupervisedChild::new(child, ChildTermination::Process)?;
    let mut output = Vec::new();
    stdout.read_to_end(&mut output)?;
    let start = Instant::now();
    assert!(
        child
            .wait_until(start + Duration::from_millis(100))?
            .is_none()
    );
    assert!(start.elapsed() >= Duration::from_millis(100));
    assert!(start.elapsed() < Duration::from_secs(5));
    child.terminate();
    assert!(
        !child
            .wait_until(deadline())?
            .ok_or("child survived cancellation")?
            .success()
    );
    Ok(())
}

#[test]
fn cancellation_wakes_a_concurrent_waiter() -> TestResult {
    let child = Command::new("sleep").arg("30").spawn()?;
    let child = Arc::new(SupervisedChild::new(child, ChildTermination::Process)?);
    let waiter = Arc::clone(&child);
    let (tx, rx) = mpsc::channel();
    let thread = thread::spawn(move || {
        let _ = tx.send(waiter.wait_until(deadline()));
    });
    child.terminate();
    let status = rx
        .recv_timeout(Duration::from_secs(5))??
        .ok_or("waiter timed out")?;
    assert!(!status.success());
    thread.join().map_err(|_| "waiter panicked")?;
    Ok(())
}

#[test]
fn cancellation_closes_descendant_pipes() -> TestResult {
    let mut child = Command::new("sh")
        .args(["-c", "sleep 30 & echo ready; wait"])
        .process_group(0)
        .stdout(Stdio::piped())
        .spawn()?;
    let stdout = child.stdout.take().ok_or("missing stdout")?;
    let child = SupervisedChild::new(child, ChildTermination::ProcessGroup)?;
    let mut stdout = BufReader::new(stdout);
    let mut ready = String::new();
    stdout.read_line(&mut ready)?;
    assert_eq!(ready, "ready\n");
    let (tx, rx) = mpsc::channel();
    let reader = thread::spawn(move || {
        let mut remaining = Vec::new();
        let _ = tx.send(stdout.read_to_end(&mut remaining));
    });
    child.terminate();
    assert!(
        !child
            .wait_until(deadline())?
            .ok_or("child survived")?
            .success()
    );
    rx.recv_timeout(Duration::from_secs(5))??;
    reader.join().map_err(|_| "reader panicked")?;
    Ok(())
}

#[test]
fn dropping_owner_cancels_and_reaps_child() -> TestResult {
    use rustix::process::{Pid, WaitId, WaitIdOptions, waitid};
    let child = Command::new("sleep").arg("30").spawn()?;
    let pid = Pid::from_raw(child.id().cast_signed()).ok_or("invalid PID")?;
    drop(SupervisedChild::new(child, ChildTermination::Process)?);
    assert_eq!(
        waitid(
            WaitId::Pid(pid),
            WaitIdOptions::EXITED | WaitIdOptions::NOHANG
        )
        .err(),
        Some(rustix::io::Errno::CHILD)
    );
    Ok(())
}

#[test]
fn accepts_a_child_with_an_already_cached_exit_status() -> TestResult {
    let mut child = Command::new("sh").args(["-c", "exit 3"]).spawn()?;
    let expected = child.wait()?;
    let child = SupervisedChild::new(child, ChildTermination::ProcessGroup)?;
    child.terminate();
    assert_eq!(child.wait_until(Instant::now())?, Some(expected));
    Ok(())
}

#[test]
fn rejects_a_child_reaped_outside_the_owner() -> TestResult {
    use rustix::process::{Pid, WaitOptions, waitpid};
    let child = Command::new("sh").args(["-c", "exit 0"]).spawn()?;
    let pid = Pid::from_raw(child.id().cast_signed()).ok_or("invalid PID")?;
    waitpid(Some(pid), WaitOptions::empty())?;
    let error = SupervisedChild::new(child, ChildTermination::ProcessGroup)
        .err()
        .ok_or("accepted a reaped child")?;
    assert_eq!(
        error.raw_os_error(),
        Some(rustix::io::Errno::CHILD.raw_os_error())
    );
    Ok(())
}

#[test]
fn ignored_sigchld_reports_lost_ownership() -> TestResult {
    const PROBE: &str = "NIX_SEAL_TEST_IGNORED_SIGCHLD";
    if std::env::var_os(PROBE).is_some() {
        let mut child = Command::new("sh")
            .args(["-c", "read line"])
            .stdin(Stdio::piped())
            .spawn()?;
        let stdin = child.stdin.take().ok_or("missing stdin")?;
        let child = SupervisedChild::new(child, ChildTermination::Process)?;
        drop(stdin);
        let error = child
            .wait_until(deadline())
            .err()
            .ok_or("missing ownership error")?;
        assert_eq!(
            error.raw_os_error(),
            Some(rustix::io::Errno::CHILD.raw_os_error())
        );
        child.terminate();
        return Ok(());
    }
    let status = Command::new("sh")
        .args(["-c", "trap '' CHLD; exec \"$@\"", "sh"])
        .arg(std::env::current_exe()?)
        .args(["--exact", "ignored_sigchld_reports_lost_ownership"])
        .env(PROBE, "1")
        .status()?;
    assert!(status.success());
    Ok(())
}
