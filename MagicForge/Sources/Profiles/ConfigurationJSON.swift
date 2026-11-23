import Foundation
import MFCore

/// JSON plumbing shared by the store and import / export.
///
/// The core model types use synthesized `Codable`, which fails on any missing key. To stay
/// readable across versions (and forgiving of hand edits) files are decoded leniently:
/// 1. parse the file into a plain JSON object,
/// 2. lay it over the JSON of a default value, struct by struct, so absent or `null` fields fall
///    back to their defaults (`LenientFiller`),
/// 3. decode the completed object with the normal `JSONDecoder`.
/// Enum payloads (triggers, actions, workflow steps) are not completed: they must be whole.
enum ConfigurationJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try makeEncoder().encode(value)
        } catch {
            throw ConfigurationError.invalid("Could not encode the data as JSON.")
        }
    }

    /// The JSON object form of a model value; used as the template that fills missing keys.
    static func template<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    /// Parses `data` as a top-level JSON object.
    static func parseObject(_ data: Data) throws -> [String: Any] {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ConfigurationError.unreadable("The file is not valid JSON.")
        }
        guard let object = parsed as? [String: Any] else {
            throw ConfigurationError.unreadable("The file does not contain a JSON object.")
        }
        return object
    }

    static func decode<T: Decodable>(_ type: T.Type, from object: Any) throws -> T {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            throw ConfigurationError.invalid("The data is not a valid JSON structure.")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw ConfigurationError.invalid(describe(error))
        } catch {
            throw ConfigurationError.invalid("The data could not be decoded.")
        }
    }

    /// Integer value of `object[key]`: nil when absent or `null`, throws when it is anything but
    /// a whole number. Goes through `JSONDecoder` because `NSNumber` cannot tell `1` from `true`
    /// the same way on every platform.
    static func integer(_ key: String, in object: [String: Any]) throws -> Int? {
        guard let value = object[key], !(value is NSNull) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: [key: value]),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data), let number = decoded[key] else {
            throw ConfigurationError.invalid("“\(key)” must be a whole number.")
        }
        return number
    }

    /// Lenient decode of a whole configuration. Throws `unsupportedSchema` for files written by
    /// a newer version and `invalid` when the structure cannot be understood.
    static func decodeConfiguration(from object: [String: Any]) throws -> Configuration {
        if let version = try integer("schemaVersion", in: object), version > Configuration.currentSchemaVersion {
            throw ConfigurationError.unsupportedSchema(version)
        }
        var filler = LenientFiller()
        return try decode(Configuration.self, from: filler.configuration(object))
    }

    /// Describes where decoding failed without echoing any value from the file.
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            return keys.isEmpty ? "the top level" : keys.joined(separator: ".")
        }
        switch error {
        case .typeMismatch(_, let context): return "Unexpected type of value at \(path(context))."
        case .valueNotFound(_, let context): return "Missing value at \(path(context))."
        case .keyNotFound(let key, let context): return "Missing field “\(key.stringValue)” at \(path(context))."
        case .dataCorrupted(let context): return "Invalid value at \(path(context))."
        @unknown default: return "The data could not be decoded."
        }
    }
}

/// Completes partially specified JSON objects with model defaults (see `ConfigurationJSON`).
struct LenientFiller {
    /// Elements that were dropped because they lacked a field with no sensible default.
    private(set) var notes: [String] = []

    private let configurationDefaults = ConfigurationJSON.template(Configuration())
    private let profileDefaults = LenientFiller.withoutID(ConfigurationJSON.template(Profile(name: "Untitled Profile")))
    private let bindingDefaults: [String: Any] = {
        var template = LenientFiller.withoutID(
            ConfigurationJSON.template(GestureBinding(trigger: .single(.oneFingerTap), action: .none)))
        template["trigger"] = nil
        return template
    }()
    private let scrollDefaults = ConfigurationJSON.template(ScrollSettings())
    private let workflowDefaults = LenientFiller.withoutID(ConfigurationJSON.template(Workflow(name: "Untitled Workflow")))
    private let menuDefaults = LenientFiller.withoutID(ConfigurationJSON.template(RadialMenu(name: "Untitled Menu")))
    private let menuItemDefaults = LenientFiller.withoutID(ConfigurationJSON.template(RadialMenuItem(title: "Item")))
    private let themeDefaults = ConfigurationJSON.template(RadialMenuTheme())
    private let keyComboDefaults: [String: Any] = {
        var template = ConfigurationJSON.template(KeyCombo(keyCode: 0))
        template["keyCode"] = nil
        return template
    }()
    private let templateDefaults = LenientFiller.withoutID(ConfigurationJSON.template(PromptTemplate(name: "Untitled Prompt")))
    private let aiDefaults = ConfigurationJSON.template(AISettings())
    private let settingsDefaults = ConfigurationJSON.template(AppSettings())
    private let recognizerDefaults = ConfigurationJSON.template(RecognizerConfig())
    private let tuningDefaults = ConfigurationJSON.template(GestureTuning())
    private let calibrationDefaults = ConfigurationJSON.template(DeviceCalibration())
    private let surfaceDefaults = ConfigurationJSON.template(SurfaceGeometry.magicMouse)

    private static func withoutID(_ template: [String: Any]) -> [String: Any] {
        var copy = template
        copy["id"] = nil
        return copy
    }

    // MARK: Model shapes

    mutating func configuration(_ loaded: [String: Any]) -> [String: Any] {
        var out = filled(loaded, with: configurationDefaults)
        out["profiles"] = elements(out["profiles"]) { $0.profile($1) }
        out["workflows"] = elements(out["workflows"]) { $0.workflow($1) }
        out["radialMenus"] = elements(out["radialMenus"]) { $0.radialMenu($1) }
        out["ai"] = object(out["ai"]) { $0.ai($1) }
        out["settings"] = object(out["settings"]) { $0.filled($1, with: $0.settingsDefaults) }
        out["recognizer"] = object(out["recognizer"]) { filler, recognizer in
            var result = filler.filled(recognizer, with: filler.recognizerDefaults)
            result["tuning"] = filler.values(result["tuning"]) { $0.filled($1, with: $0.tuningDefaults) }
            return result
        }
        out["calibrations"] = values(out["calibrations"]) { filler, calibration in
            var result = filler.filled(calibration, with: filler.calibrationDefaults)
            result["surface"] = filler.object(result["surface"]) { $0.filled($1, with: $0.surfaceDefaults) }
            return result
        }
        return out
    }

    mutating func profile(_ loaded: [String: Any]) -> [String: Any]? {
        var out = identified(filled(loaded, with: profileDefaults))
        out["bindings"] = elements(out["bindings"]) { filler, binding in
            guard binding["trigger"] != nil, !(binding["trigger"] is NSNull) else {
                filler.notes.append("A binding without a trigger was skipped.")
                return nil
            }
            return filler.identified(filler.filled(binding, with: filler.bindingDefaults))
        }
        if out["scroll"] != nil {
            out["scroll"] = object(out["scroll"]) { $0.filled($1, with: $0.scrollDefaults) }
        }
        return out
    }

    mutating func workflow(_ loaded: [String: Any]) -> [String: Any]? {
        identified(filled(loaded, with: workflowDefaults))
    }

    mutating func radialMenu(_ loaded: [String: Any]) -> [String: Any]? {
        var out = identified(filled(loaded, with: menuDefaults))
        out["theme"] = object(out["theme"]) { $0.filled($1, with: $0.themeDefaults) }
        out["items"] = elements(out["items"]) { $0.menuItem($1, depth: 0) }
        if out["hotKey"] != nil {
            out["hotKey"] = object(out["hotKey"]) { $0.filled($1, with: $0.keyComboDefaults) }
        }
        return out
    }

    private mutating func menuItem(_ loaded: [String: Any], depth: Int) -> [String: Any]? {
        var out = identified(filled(loaded, with: menuItemDefaults))
        // Far deeper than any valid menu; guards against pathological nesting.
        if depth >= 16 {
            out["children"] = [Any]()
            return out
        }
        out["children"] = elements(out["children"]) { $0.menuItem($1, depth: depth + 1) }
        return out
    }

    mutating func promptTemplate(_ loaded: [String: Any]) -> [String: Any]? {
        identified(filled(loaded, with: templateDefaults))
    }

    private mutating func ai(_ loaded: [String: Any]) -> [String: Any] {
        var out = filled(loaded, with: aiDefaults)
        out["templates"] = elements(out["templates"]) { $0.promptTemplate($1) }
        return out
    }

    // MARK: Building blocks

    /// `loaded` with every absent or `null` key taken from `defaults`.
    private func filled(_ loaded: [String: Any], with defaults: [String: Any]) -> [String: Any] {
        var out = loaded
        for (key, value) in defaults where out[key] == nil || out[key] is NSNull {
            out[key] = value
        }
        return out
    }

    private func identified(_ object: [String: Any]) -> [String: Any] {
        var out = object
        if out["id"] == nil || out["id"] is NSNull { out["id"] = UUID().uuidString }
        return out
    }

    /// Applies `transform` to a nested object; anything else is passed through so that decoding
    /// reports the type error.
    private mutating func object(_ value: Any?, _ transform: (inout LenientFiller, [String: Any]) -> [String: Any]) -> Any? {
        guard let dictionary = value as? [String: Any] else { return value }
        return transform(&self, dictionary)
    }

    /// Applies `transform` to each object in an array; returning nil drops the element.
    mutating func elements(_ value: Any?,
                                   _ transform: (inout LenientFiller, [String: Any]) -> [String: Any]?) -> Any? {
        guard let array = value as? [Any] else { return value }
        var result: [Any] = []
        result.reserveCapacity(array.count)
        for element in array {
            if let dictionary = element as? [String: Any] {
                if let transformed = transform(&self, dictionary) { result.append(transformed) }
            } else {
                result.append(element)
            }
        }
        return result
    }

    /// Applies `transform` to each object value of a string-keyed map.
    private mutating func values(_ value: Any?, _ transform: (inout LenientFiller, [String: Any]) -> [String: Any]) -> Any? {
        guard let dictionary = value as? [String: Any] else { return value }
        var result: [String: Any] = [:]
        for (key, element) in dictionary {
            if let nested = element as? [String: Any] {
                result[key] = transform(&self, nested)
            } else {
                result[key] = element
            }
        }
        return result
    }
}
