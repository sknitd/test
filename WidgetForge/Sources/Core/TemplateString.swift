import Foundation

/// Resolves `{{path | filter:arg}}` placeholders against a JSON data context.
///
/// This is the *only* expression language available to declarative widgets. It can read values and format
/// them; it cannot call functions, loop, or reach anything outside the context it is handed.
enum TemplateRenderer {
    /// Render a template to a display string.
    static func render(_ template: String, context: JSONValue, now: Date = Date()) -> String {
        guard template.contains("{{") else { return template }
        var out = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            out += rest[rest.startIndex..<open.lowerBound]
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "}}") else {
                out += rest[open.lowerBound...]
                return out
            }
            out += evaluate(String(after[after.startIndex..<close.lowerBound]), context: context, now: now).displayString
            rest = after[close.upperBound...]
        }
        out += rest
        return out
    }

    /// Resolve a prop value. A string that is exactly one placeholder keeps its JSON type (number, array…),
    /// which is how charts, gauges and lists receive structured data.
    static func resolve(_ value: JSONValue, context: JSONValue, now: Date = Date()) -> JSONValue {
        guard case .string(let s) = value else { return value }
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("{{"), t.hasSuffix("}}"), t.dropFirst(2).range(of: "{{") == nil {
            return evaluate(String(t.dropFirst(2).dropLast(2)), context: context, now: now)
        }
        return .string(render(s, context: context, now: now))
    }

    /// Evaluate the inside of one placeholder.
    static func evaluate(_ expression: String, context: JSONValue, now: Date = Date()) -> JSONValue {
        let parts = expression.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let head = parts.first, !head.isEmpty else { return .null }
        var value: JSONValue
        if head == "now" {
            value = .number(now.timeIntervalSince1970)
        } else if let literal = Double(head) {
            value = .number(literal)
        } else if head.hasPrefix("'"), head.hasSuffix("'"), head.count >= 2 {
            value = .string(String(head.dropFirst().dropLast()))
        } else {
            value = context.path(head) ?? .null
        }
        for filter in parts.dropFirst() {
            let pieces = filter.split(separator: ":", maxSplits: 1).map(String.init)
            value = apply(pieces[0], arg: pieces.count > 1 ? pieces[1] : nil, to: value, now: now)
        }
        return value
    }

    static func apply(_ name: String, arg: String?, to value: JSONValue, now: Date) -> JSONValue {
        let number = value.doubleValue
        let argNumber = arg.flatMap(Double.init)
        switch name {
        case "percent":
            guard let n = number else { return "–" }
            return .string(JSONValue.format(n * 100, maxFractionDigits: Int(argNumber ?? 0)) + "%")
        case "round":
            guard let n = number else { return value }
            let p = pow(10.0, argNumber ?? 0)
            return .number((n * p).rounded() / p)
        case "fixed":
            guard let n = number else { return "–" }
            return .string(String(format: "%.\(Int(argNumber ?? 2))f", n))
        case "mul": return number.map { .number($0 * (argNumber ?? 1)) } ?? value
        case "div": return number.map { .number(argNumber == 0 ? 0 : $0 / (argNumber ?? 1)) } ?? value
        case "add": return number.map { .number($0 + (argNumber ?? 0)) } ?? value
        case "bytes": return number.map { .string(Formatters.bytes($0)) } ?? "–"
        case "rate": return number.map { .string(Formatters.bytes($0) + "/s") } ?? "–"
        case "duration": return number.map { .string(Formatters.duration($0)) } ?? "–"
        case "currency":
            guard let n = number else { return "–" }
            return .string((arg ?? "$") + String(format: "%.2f", n))
        case "signed":
            guard let n = number else { return "–" }
            return .string((n >= 0 ? "+" : "") + JSONValue.format(n, maxFractionDigits: Int(argNumber ?? 2)))
        case "upper": return .string(value.displayString.uppercased())
        case "lower": return .string(value.displayString.lowercased())
        case "default":
            if value.isNull || value.stringValue == "" { return .string(arg ?? "") }
            return value
        case "count":
            if let a = value.arrayValue { return .number(Double(a.count)) }
            if let o = value.objectValue { return .number(Double(o.count)) }
            return 0
        case "first": return value.arrayValue?.first ?? .null
        case "last": return value.arrayValue?.last ?? .null
        case "limit":
            guard let a = value.arrayValue else { return value }
            return .array(Array(a.prefix(Int(argNumber ?? 5))))
        case "pluck":
            guard let a = value.arrayValue, let key = arg else { return value }
            return .array(a.map { $0.path(key) ?? .null })
        case "join":
            guard let a = value.arrayValue else { return value }
            return .string(a.map(\.displayString).joined(separator: arg ?? ", "))
        case "yesno": return .string(value.boolValue == true ? "Yes" : "No")
        case "truncate":
            let s = value.displayString
            let n = Int(argNumber ?? 40)
            return .string(s.count > n ? String(s.prefix(n)) + "…" : s)
        case "date":
            guard let date = Formatters.date(from: value) else { return value }
            let f = DateFormatter()
            f.dateFormat = arg ?? "MMM d, HH:mm"
            return .string(f.string(from: date))
        case "relative":
            guard let date = Formatters.date(from: value) else { return value }
            return .string(Formatters.relative(date.timeIntervalSince(now)))
        case "until":
            guard let date = Formatters.date(from: value) else { return value }
            return .number(date.timeIntervalSince(now))
        default:
            return value
        }
    }
}

enum Formatters {
    static func bytes(_ value: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var v = max(0, value)
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        return i == 0 ? "\(Int(v)) B" : String(format: v >= 100 ? "%.0f" : "%.1f", v) + " " + units[i]
    }

    /// 93784 -> "1d 2h 3m"
    static func duration(_ seconds: Double) -> String {
        var s = Int(abs(seconds))
        let d = s / 86400; s %= 86400
        let h = s / 3600; s %= 3600
        let m = s / 60; s %= 60
        if d > 0 { return "\(d)d \(h)h \(m)m" }
        if h > 0 { return m == 0 ? "\(h)h" : "\(h)h \(m)m" }
        if m > 0 { return s == 0 ? "\(m)m" : "\(m)m \(s)s" }
        return "\(s)s"
    }

    static func relative(_ delta: Double) -> String {
        let text = duration(delta)
        return delta < 0 ? "\(text) ago" : "in \(text)"
    }

    /// mm:ss, or h:mm:ss when at least one hour.
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
                         : String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func date(from value: JSONValue) -> Date? {
        if let n = value.doubleValue, case .number = value {
            return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n)
        }
        guard let s = value.stringValue else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

/// A structured comparison used by automation conditions, thresholds and API-response triggers.
struct Condition: Codable, Hashable, Sendable {
    enum Operator: String, Codable, CaseIterable, Sendable {
        case lessThan = "<", lessOrEqual = "<=", greaterThan = ">", greaterOrEqual = ">="
        case equals = "==", notEquals = "!=", contains, exists
    }
    var path: String
    var op: Operator
    var value: JSONValue

    init(_ path: String, _ op: Operator, _ value: JSONValue = .null) {
        self.path = path; self.op = op; self.value = value
    }

    func evaluate(in context: JSONValue) -> Bool {
        let lhs = context.path(path)
        switch op {
        case .exists: return lhs != nil && lhs?.isNull == false
        case .contains:
            guard let lhs else { return false }
            if let a = lhs.arrayValue { return a.contains(value) }
            return lhs.displayString.localizedCaseInsensitiveContains(value.displayString)
        case .equals, .notEquals:
            let equal: Bool
            if let l = lhs, case .number(let a) = l, let b = value.doubleValue { equal = a == b }
            else if let l = lhs, case .bool(let a) = l, let b = value.boolValue { equal = a == b }
            else { equal = (lhs ?? .null).displayString == value.displayString }
            return op == .equals ? equal : !equal
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            guard let a = lhs?.doubleValue, let b = value.doubleValue else { return false }
            switch op {
            case .lessThan: return a < b
            case .lessOrEqual: return a <= b
            case .greaterThan: return a > b
            default: return a >= b
            }
        }
    }

    var summary: String { op == .exists ? "\(path) exists" : "\(path) \(op.rawValue) \(value.displayString)" }
}
