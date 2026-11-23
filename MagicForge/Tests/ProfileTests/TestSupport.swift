import Foundation
import XCTest
import MFCore
@testable import MFProfiles

enum Fixtures {
    static let allCapabilities = InputCapabilities(rawContacts: true, maxContacts: 5, contactSize: true, pointerEvents: true)
    static let fallbackOnly = InputCapabilities(rawContacts: false, maxContacts: 0, contactSize: false, pointerEvents: true)

    static func binding(_ kind: GestureKind, _ action: Action = .system(.missionControl), enabled: Bool = true,
                        priority: Int = 0, sensitivity: Double = 0.5, duration: TimeInterval? = nil) -> GestureBinding {
        GestureBinding(trigger: .single(kind), action: action, isEnabled: enabled, sensitivity: sensitivity,
                       duration: duration, priority: priority)
    }

    /// A small valid configuration: a global profile plus whatever is passed in.
    static func configuration(global bindings: [GestureBinding] = [], profiles: [Profile] = []) -> Configuration {
        var configuration = Configuration()
        let global = Profile(id: configuration.globalProfileID, name: "Global", bindings: bindings, scroll: ScrollSettings())
        configuration.profiles = [global] + profiles
        return configuration
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mf-profile-tests-\(UUID().uuidString)", isDirectory: true)
    }

    static func json(_ object: Any) -> Data {
        // Test fixtures are always valid JSON objects.
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

extension XCTestCase {
    func assertThrowsConfigurationError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath,
                                        line: UInt = #line, _ check: (ConfigurationError) -> Void = { _ in }) {
        do {
            _ = try expression()
            XCTFail("Expected a ConfigurationError", file: file, line: line)
        } catch let error as ConfigurationError {
            check(error)
        } catch {
            XCTFail("Expected a ConfigurationError, got \(error)", file: file, line: line)
        }
    }
}
