import AppKit
import Foundation

@main
struct OpenStaffCaptureCLI {
    static func main() {
        do {
            let options = try CaptureCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)

            let permissionChecker = AccessibilityPermissionChecker()
            guard permissionChecker.isTrusted(prompt: options.promptForPermission) else {
                print("[CAP-PERMISSION-DENIED] Accessibility permission is required for global capture.")
                print("Open System Settings > Privacy & Security > Accessibility and allow your terminal app, then rerun this command.")
                Foundation.exit(2)
            }

            let engine = MouseCaptureEngine(
                sessionId: options.sessionId,
                maxEvents: options.maxEvents,
                printJSON: options.printJSON
            )

            let signalTrap = SignalTrap {
                engine.stop()
                print("Capture stopped by signal. total=\(engine.capturedCount)")
                CFRunLoopStop(CFRunLoopGetMain())
            }

            engine.onStopRequested = {
                engine.stop()
                print("Capture stopped after reaching max events. total=\(engine.capturedCount)")
                CFRunLoopStop(CFRunLoopGetMain())
            }

            try engine.start()
            print("Capture started. sessionId=\(options.sessionId)")
            print("Press Ctrl+C to stop.")
            if let maxEvents = options.maxEvents {
                print("Auto-stop after \(maxEvents) events.")
            }

            withExtendedLifetime(signalTrap) {
                RunLoop.main.run()
            }
        } catch {
            print("Capture startup failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffCaptureCLI

        Usage:
          make capture
          make capture ARGS=\"--session-id session-20260307-a1 --max-events 20\"

        Flags:
          --session-id <id>           Set a custom session ID.
          --max-events <n>            Stop automatically after n captured events.
          --json                      Print raw events as JSONL lines.
          --no-permission-prompt      Do not trigger macOS accessibility permission prompt.
          --help                      Show this help message.
        """)
    }
}

struct CaptureCLIOptions {
    let sessionId: String
    let maxEvents: Int?
    let printJSON: Bool
    let promptForPermission: Bool
    let showHelp: Bool

    static func parse(arguments: [String]) throws -> CaptureCLIOptions {
        var sessionId: String?
        var maxEvents: Int?
        var printJSON = false
        var promptForPermission = true
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--session-id":
                index += 1
                guard index < arguments.count else {
                    throw CaptureCLIOptionError.missingValue("--session-id")
                }
                sessionId = arguments[index]
            case "--max-events":
                index += 1
                guard index < arguments.count else {
                    throw CaptureCLIOptionError.missingValue("--max-events")
                }

                guard let parsed = Int(arguments[index]), parsed > 0 else {
                    throw CaptureCLIOptionError.invalidValue("--max-events", arguments[index])
                }

                maxEvents = parsed
            case "--json":
                printJSON = true
            case "--no-permission-prompt":
                promptForPermission = false
            case "--help", "-h":
                showHelp = true
            default:
                throw CaptureCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        return CaptureCLIOptions(
            sessionId: sessionId ?? defaultSessionId(),
            maxEvents: maxEvents,
            printJSON: printJSON,
            promptForPermission: promptForPermission,
            showHelp: showHelp
        )
    }

    private static func defaultSessionId() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return "session-\(formatter.string(from: Date()))"
    }
}

enum CaptureCLIOptionError: LocalizedError {
    case missingValue(String)
    case invalidValue(String, String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)."
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag). Use --help to see supported flags."
        }
    }
}

final class SignalTrap {
    private let source: DispatchSourceSignal

    init(handler: @escaping () -> Void) {
        Foundation.signal(SIGINT, SIG_IGN)
        source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler(handler: handler)
        source.resume()
    }
}
