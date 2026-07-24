import AppKit
import Foundation

/// Parsed command-line options.
struct CLIOptions {
    /// nil = leave the default (checkbox) value untouched.
    var autoRestore: Bool?
    /// Monitor to auto-open an overlay on at launch (nil = don't auto-open).
    var monitorSelector: String?
    /// Override the overlay URL (raw text; scheme normalized when used).
    var urlString: String?
    var showHelp = false

    static let helpText = """
    Monitor Overlay — list displays and open borderless web overlays on them.

    Usage: Monitor Overlay [options]

    Options:
      -m, --monitor <selector>   Auto-open an overlay on a monitor at launch.
                                 <selector> is one of:
                                   <n>            1-based index in the list (e.g. 1)
                                   main           the current main display
                                   id:<id>        a CGDirectDisplayID
                                   uuid:<uuid>    a stable display UUID
          --auto-restore <val>   Auto-restore overlay when its monitor reconnects.
                                 <val> is on|off|true|false|yes|no (default: on).
          --no-auto-restore      Shorthand for --auto-restore off.
      -u, --url <url>            Overlay URL (default: https://www.google.com).
      -h, --help                 Show this help and exit.

    Examples:
      Monitor Overlay --monitor 2 --no-auto-restore
      Monitor Overlay -m main -u https://apple.com
      Monitor Overlay --monitor uuid:37D8832A-2D66-02CA-B9F7-8F30A301B230
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
            case "--auto-restore":
                if let raw = value(after: name, inline: inline) { opts.autoRestore = parseBool(raw) }
            case "--no-auto-restore":
                opts.autoRestore = false
            default:
                FileHandle.standardError.write(Data("Unknown option: \(token)\n".utf8))
            }
        }
        return opts
    }

    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "on", "true", "yes", "1": return true
        case "off", "false", "no", "0": return false
        default: return nil
        }
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
