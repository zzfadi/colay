import Foundation

/// A JSON-like parameter bag with typed accessors. Every Command builds itself from one of
/// these. Using a neutral dict here — instead of making each command `Decodable` — keeps
/// two doors open:
///   1. Hand-authored scripts (current use case)
///   2. Future AI tool-call protocol (e.g. an LLM passes JSON args verbatim)
/// without having to maintain two parallel schemas.
struct CommandParams {
    let raw: [String: Any]

    init(_ raw: [String: Any]) { self.raw = raw }

    func string(_ key: String) -> String? { raw[key] as? String }
    func bool(_ key: String) -> Bool? { raw[key] as? Bool }
    func double(_ key: String) -> Double? {
        if let v = raw[key] as? Double { return v }
        if let v = raw[key] as? Int { return Double(v) }
        return nil
    }
    func int(_ key: String) -> Int? {
        if let v = raw[key] as? Int { return v }
        if let v = raw[key] as? Double { return Int(v) }
        return nil
    }

    func point(_ key: String) -> CGPoint? {
        if let d = raw[key] as? [String: Any] {
            let x = (d["x"] as? Double) ?? (d["x"] as? Int).map(Double.init) ?? 0
            let y = (d["y"] as? Double) ?? (d["y"] as? Int).map(Double.init) ?? 0
            return CGPoint(x: x, y: y)
        }
        if let a = raw[key] as? [Any], a.count >= 2 {
            let x = (a[0] as? Double) ?? (a[0] as? Int).map(Double.init) ?? 0
            let y = (a[1] as? Double) ?? (a[1] as? Int).map(Double.init) ?? 0
            return CGPoint(x: x, y: y)
        }
        return nil
    }

    func easing(_ key: String) -> Easing {
        if let s = raw[key] as? String, let e = Easing(rawValue: s) { return e }
        return .easeInOut
    }

    /// Nested child array of command params (for composites like `repeat`, `parallel`).
    func children(_ key: String = "actions") -> [(String, CommandParams)] {
        guard let arr = raw[key] as? [Any] else { return [] }
        return arr.compactMap { item -> (String, CommandParams)? in
            guard let d = item as? [String: Any], let t = d["type"] as? String else { return nil }
            var rest = d; rest.removeValue(forKey: "type")
            return (t, CommandParams(rest))
        }
    }
}

/// Minimal JSON Schema-ish descriptor for tool-calling surfaces.
struct CommandSchema {
    struct Param {
        let name: String
        let type: String   // "number", "string", "point", "bool", "easing", "actions"
        let required: Bool
        let description: String
    }
    let type: String
    let summary: String
    let params: [Param]
}
