import Foundation

/// Startup gating that must run before AppKit/SwiftUI initializes.
enum Bootstrap {
    private static let detachedEnvKey = "MONITOR_OVERLAY_DETACHED"
    /// Held for the whole process lifetime so the single-instance lock persists.
    private static var lockFileDescriptor: Int32 = -1

    /// If launched attached to a terminal, relaunch a detached copy (stdio → /dev/null)
    /// and exit, so the shell prompt returns and the app keeps running independently.
    static func detachFromTerminalIfNeeded() {
        // The relaunched child carries this flag — don't detach again.
        if ProcessInfo.processInfo.environment[detachedEnvKey] == "1" { return }
        // Only detach when actually attached to a TTY (not when launched by Finder/launchd).
        guard isatty(STDIN_FILENO) != 0 || isatty(STDOUT_FILENO) != 0 else { return }
        guard let executable = Bundle.main.executablePath else { return }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = Array(CommandLine.arguments.dropFirst())
        var environment = ProcessInfo.processInfo.environment
        environment[detachedEnvKey] = "1"
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice

        do {
            try child.run()
            exit(0) // parent exits → terminal is freed; child runs on
        } catch {
            // Relaunch failed — fall through and just run in the foreground.
        }
    }

    static let restartFlags = ["--restart", "--force-restart"]
    private static let lockPath = NSTemporaryDirectory() + "monitor-overlay.lock"

    /// Ensure only one instance runs. By default a second launch exits immediately
    /// (nothing happens). With `--restart`, it instead terminates the running
    /// instance and takes over. Uses an advisory file lock (auto-released if the
    /// holder dies, so no stale-lock problem) whose contents hold the owner's PID.
    static func enforceSingleInstance() {
        let forceRestart = CommandLine.arguments.contains { restartFlags.contains($0) }

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return } // couldn't open — don't block startup

        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            // Another instance holds the lock.
            guard forceRestart else {
                close(fd)
                exit(0)
            }
            terminateRunningInstance()
            guard waitForLock(fd) else {
                close(fd) // couldn't take over in time — bail rather than run a second copy
                exit(1)
            }
        }

        writeOwnerPID(to: fd)
        lockFileDescriptor = fd // intentionally kept open until the process exits
    }

    /// SIGTERM (then SIGKILL) the PID recorded in the lock file.
    private static func terminateRunningInstance() {
        guard let contents = try? String(contentsOfFile: lockPath, encoding: .utf8),
              let pid = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else { return }

        kill(pid, SIGTERM)
        for _ in 0..<20 { // wait up to ~2s for a clean exit
            if kill(pid, 0) != 0 { return } // gone
            usleep(100_000)
        }
        kill(pid, SIGKILL) // still alive — force it
    }

    /// Poll for the advisory lock to free up after the old instance dies.
    private static func waitForLock(_ fd: Int32) -> Bool {
        for _ in 0..<50 { // up to ~5s
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return true }
            usleep(100_000)
        }
        return false
    }

    /// Record our PID in the lock file so a future `--restart` can find us.
    private static func writeOwnerPID(to fd: Int32) {
        ftruncate(fd, 0)
        lseek(fd, 0, SEEK_SET)
        let line = "\(getpid())\n"
        _ = line.withCString { write(fd, $0, strlen($0)) }
        fsync(fd)
    }
}
