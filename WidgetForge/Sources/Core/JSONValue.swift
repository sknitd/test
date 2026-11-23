import Foundation

/// A lossless, Codable representation of arbitrary JSON. All widget props, widget state and data-source
/// payloads flow through this type so that nothing dynamic ever needs `Any`.
enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let d):
            if d.isFinite, d == d.rounded(), abs(d) < 9e15 { try c.encode(Int64(d)) } else if d.isFinite { try c.encode(d) } else { try c.encodeNil() }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral, ExpressibleByStringLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(nilLiteral: ()) { self = .null }
    init(booleanLiteral value: Bool) { self = .bool(value) }
    init(integerLiteral value: Int) { self = .number(Double(value)) }
    init(floatLiteral value: Double) { self = .number(value) }
    init(stringLiteral value: String) { self = .string(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        var o: [String: JSONValue] = [:]
        for (k, v) in elements { o[k] = v }
        self = .object(o)
    }
}

extension JSONValue {
    var isNull: Bool { if case .null = self { return true }; return false }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .number(let d): return d != 0
        case .string(let s): return ["true", "yes", "1"].contains(s.lowercased()) ? true : (["false", "no", "0"].contains(s.lowercased()) ? false : nil)
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .number(let d): return d
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }
    var intValue: Int? { doubleValue.flatMap { $0.isFinite ? Int($0) : nil } }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    subscript(key: String) -> JSONValue? { objectValue?[key] }
    subscript(index: Int) -> JSONValue? {
        guard let a = arrayValue, index >= 0, index < a.count else { return nil }
        return a[index]
    }

    /// Human readable text for display in a widget.
    var displayString: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .number(let d): return JSONValue.format(d)
        case .string(let s): return s
        case .array(let a): return a.map(\.displayString).joined(separator: ", ")
        case .object: return compactJSONString
        }
    }

    static func format(_ d: Double, maxFractionDigits: Int = 2) -> String {
        guard d.isFinite else { return "–" }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        let p = pow(10.0, Double(maxFractionDigits))
        let r = (d * p).rounded() / p
        if r == r.rounded() { return String(Int64(r)) }
        var s = String(format: "%.\(maxFractionDigits)f", r)
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    var compactJSONString: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    var prettyJSONString: String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return (try? enc.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    static func parse(_ data: Data) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: data) }
    static func parse(_ text: String) throws -> JSONValue { try parse(Data(text.utf8)) }

    /// Convert any Encodable into a JSONValue (round trip through JSON).
    static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        try parse(JSONEncoder().encode(value))
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }

    /// Resolve a dotted path such as `data.items[0].price` or `items.0.price`.
    func path(_ path: String) -> JSONValue? {
        var current = self
        for token in JSONValue.pathTokens(path) {
            switch token {
            case .key(let k):
                if let next = current[k] { current = next }
                else if k == "count", let a = current.arrayValue { current = .number(Double(a.count)) }
                else if k == "last", let a = current.arrayValue, let l = a.last { current = l }
                else if k == "first", let a = current.arrayValue, let f = a.first { current = f }
                else { return nil }
            case .index(let i):
                guard let a = current.arrayValue else { return nil }
                let idx = i < 0 ? a.count + i : i
                guard idx >= 0, idx < a.count else { return nil }
                current = a[idx]
            }
        }
        return current
    }

    enum PathToken: Equatable { case key(String), index(Int) }

    static func pathTokens(_ path: String) -> [PathToken] {
        var tokens: [PathToken] = []
        var buffer = ""
        func flush() {
            guard !buffer.isEmpty else { return }
            if let i = Int(buffer) { tokens.append(.index(i)) } else { tokens.append(.key(buffer)) }
            buffer = ""
        }
        for ch in path.trimmingCharacters(in: .whitespaces) {
            switch ch {
            case ".", "[": flush()
            case "]": flush()
            case "$": continue
            default: buffer.append(ch)
            }
        }
        flush()
        return tokens
    }

    /// Returns a copy with `value` written at a top-level-or-nested object path (objects are created as needed).
    func setting(_ path: String, to value: JSONValue) -> JSONValue {
        let tokens = JSONValue.pathTokens(path)
        return JSONValue.set(self, tokens[...], value)
    }

    private static func set(_ node: JSONValue, _ tokens: ArraySlice<PathToken>, _ value: JSONValue) -> JSONValue {
        guard let head = tokens.first else { return value }
        let rest = tokens.dropFirst()
        switch head {
        case .key(let k):
            var o = node.objectValue ?? [:]
            o[k] = set(o[k] ?? .null, rest, value)
            return .object(o)
        case .index(let i):
            var a = node.arrayValue ?? []
            while a.count <= i { a.append(.null) }
            if i >= 0 { a[i] = set(a[i], rest, value) }
            return .array(a)
        }
    }

    /// Total number of nodes; used for resource limits.
    var nodeCount: Int {
        switch self {
        case .array(let a): return 1 + a.reduce(0) { $0 + $1.nodeCount }
        case .object(let o): return 1 + o.values.reduce(0) { $0 + $1.nodeCount }
        default: return 1
        }
    }
}
