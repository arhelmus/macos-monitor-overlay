import AppKit
import Foundation

/// Parsed command-line options.
struct CLIOptions {
    /// Monitor to auto-open an overlay on at launch (nil = don't auto-open).
    var monitorSelector: String?
    /// Override the overlay URL (raw text; scheme normalized when used).
    var urlString: String?
    var showHelp = false

    static let helpText = """
    Monitor Overlay — list displays and open borderless web overlays on them.

    Usage: MonitorOverlay [options]

    Options:
      -m, --monitor <selector>   Auto-open an overlay on a monitor at launch.
                                 <selector> is one of:
                                   <n>            1-based index in the list (e.g. 1)
                                   main           the current main display
                                   id:<id>        a CGDirectDisplayID
                                   uuid:<uuid>    a stable display UUID
      -u, --url <url>            Overlay URL (default: https://www.google.com).
          --restart              Terminate an already-running instance and take
                                 over, instead of exiting (the default).
      -h, --help                 Show this help and exit.

    Examples:
      MonitorOverlay --monitor 2 --url apple.com
      MonitorOverlay -m main -u https://apple.com
      MonitorOverlay --monitor uuid:37D8832A-2D66-02CA-B9F7-8F30A301B230
    """

    static func parse(_ args: [String]) -> CLIOptions {
        var opts = CLIOptions()
        var iterator = args.makeIterator()

        // Pull the value for a flag, supporting both "--flag value" and "--flag=value".
        func value(after flag: String, inline: String?) -> String? {
            if let inline { return inline }
            return iterator.next()
        }

        while let token = iterator.next() {
            // Split "--flag=value" into name + inline value.
            let name: String
            let inline: String?
            if let eq = token.firstIndex(of: "="), token.hasPrefix("-") {
                name = String(token[..<eq])
                inline = String(token[token.index(after: eq)...])
            } else {
                name = token
                inline = nil
            }

            switch name {
            case "-h", "--help":
                opts.showHelp = true
            case "-m", "--monitor":
                opts.monitorSelector = value(after: name, inline: inline)
            case "-u", "--url":
                if let raw = value(after: name, inline: inline) { opts.urlString = raw }
            case "--restart", "--force-restart":
                break // handled in Bootstrap before the app launches
            default:
                FileHandle.standardError.write(Data("Unknown option: \(token)\n".utf8))
            }
        }
        return opts
    }
}

/// Resolve a --monitor selector against the enumerated displays.
func resolveMonitor(_ selector: String, in monitors: [MonitorInfo]) -> MonitorInfo? {
    if selector.lowercased() == "main" {
        return monitors.first(where: \.isMain) ?? monitors.first
    }
    if let rest = selector.dropPrefixIfPresent("id:"),
       let id = CGDirectDisplayID(rest) {
        return monitors.first { $0.id == id }
    }
    if let rest = selector.dropPrefixIfPresent("uuid:") {
        return monitors.first { DisplayIdentity.uuid(for: $0.id)?.caseInsensitiveCompare(rest) == .orderedSame }
    }
    if let index = Int(selector), index >= 1, index <= monitors.count {
        return monitors[index - 1]
    }
    return nil
}

private extension String {
    /// Return the remainder after `prefix`, or nil if this string doesn't start with it.
    func dropPrefixIfPresent(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
