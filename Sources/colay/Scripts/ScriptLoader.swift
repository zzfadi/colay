import Foundation

/// Loads + parses a script JSON into a list of (type, params) pairs. The Scheduler turns
/// those into Commands via the CommandRegistry, so this file knows nothing about any
/// specific command — it's purely a parser.
enum ScriptLoader {

    struct ParsedProgram {
        let name: String
        let loop: Bool
        let actions: [(String, CommandParams)]
    }

    static func load(from url: URL) throws -> ParsedProgram {
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            throw NSError(domain: "colay.script", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Root must be an object"])
        }
        let name = (dict["name"] as? String) ?? url.lastPathComponent
        let loop = (dict["loop"] as? Bool) ?? false
        let arr = (dict["actions"] as? [Any]) ?? []
        let actions: [(String, CommandParams)] = arr.compactMap { item in
            guard let d = item as? [String: Any], let type = d["type"] as? String else { return nil }
            var rest = d; rest.removeValue(forKey: "type")
            return (type, CommandParams(rest))
        }
        return ParsedProgram(name: name, loop: loop, actions: actions)
    }
}
