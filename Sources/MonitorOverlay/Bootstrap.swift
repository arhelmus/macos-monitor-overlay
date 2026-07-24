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

    /// Ensure only one instance runs. A second launch exits immediately (no window,
    /// nothing happens). Uses an advisory file lock, which the OS releases
    /// automatically if the holding process dies — so no stale-lock problem.
    static func enforceSingleInstance() {
        let lockPath = NSTemporaryDirectory() + "monitor-overlay.lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return } // couldn't open — don't block startup
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            exit(0) // another instance already holds the lock
        }
        lockFileDescriptor = fd // intentionally kept open until the process exits
    }
}
