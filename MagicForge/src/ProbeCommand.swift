import CoreFoundation
import Foundation

/// Argument parsing and dispatch for `mfprobe`.
enum ProbeCommand {
    static let defaultDuration: TimeInterval = 15

    static let usage: String = """
    mfprobe — MagicForge input-acquisition probe

    USAGE
      mfprobe --self-check [--attempt-tap]
          No hardware needed. Reports OS / architecture, whether the private
          MultitouchSupport.framework loads, which symbols resolve, the touch struct layout,
          multitouch devices, HID Magic Mouse matches, permissions and event-tap creation.
          Prints a JSON block and exits 0 even when things are missing.
          The event-tap test is skipped when the needed permission is absent, because trying
          could show a system prompt; --attempt-tap tries anyway.
      mfprobe --devices
          Lists Magic Mouse HID devices and multitouch devices.
      mfprobe --frames [seconds]
          Streams contact frames from a Magic Mouse for the given time (default 15 s).
      mfprobe --gestures [seconds]
          Feeds frames into the gesture recognizer and prints recognized gestures.
      mfprobe --help

    OPTIONS
      --all-devices   With --frames / --gestures: also stream trackpads (diagnostics only).
      --invert-y      With --frames / --gestures: flip the vertical axis.

    Touch data comes from Apple's PRIVATE MultitouchSupport.framework and is unsupported.
    Press Control-C to stop a streaming mode early.
    """

    enum Mode {
        case help, selfCheck, devices, frames, gestures
    }

    static func run(arguments: [String]) -> Int32 {
        var mode: Mode?
        var duration: TimeInterval = defaultDuration
        var allDevices = false
        var invertY = false
        var attemptTap = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h": mode = .help
            case "--self-check": mode = .selfCheck
            case "--devices": mode = .devices
            case "--frames", "--gestures":
                mode = argument == "--frames" ? .frames : .gestures
                if index + 1 < arguments.count, let seconds = TimeInterval(arguments[index + 1]), seconds > 0 {
                    duration = seconds
                    index += 1
                }
            case "--all-devices": allDevices = true
            case "--invert-y": invertY = true
            case "--attempt-tap": attemptTap = true
            default:
                ProbeOutput.error("Unknown argument: \(argument)\n")
                print(usage)
                return 64
            }
            index += 1
        }
        if mode == nil && allDevices { mode = .devices }
        guard let selected = mode else {
            print(usage)
            return 0
        }
        switch selected {
        case .help:
            print(usage)
            return 0
        case .selfCheck:
            return SelfCheck.run(attemptTap: attemptTap)
        case .devices:
            return DeviceListing.run()
        case .frames:
            return StreamingProbe.run(mode: .frames, duration: duration, allDevices: allDevices, invertY: invertY)
        case .gestures:
            return StreamingProbe.run(mode: .gestures, duration: duration, allDevices: allDevices, invertY: invertY)
        }
    }
}

enum ProbeOutput {
    static func error(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }

    static func format(_ value: Double, digits: Int = 3) -> String {
        String(format: "%.\(digits)f", value)
    }
}
