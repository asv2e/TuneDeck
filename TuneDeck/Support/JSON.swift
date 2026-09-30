import Foundation

/// Safe path lookup through untyped JSON: `dig(json, "contents", 0, "title")`.
/// Strings index dictionaries, integers index arrays; any miss returns nil.
func dig(_ node: Any?, _ path: Any...) -> Any? {
    var current = node
    for step in path {
        if let key = step as? String {
            current = (current as? [String: Any])?[key]
        } else if let index = step as? Int {
            guard let array = current as? [Any], array.indices.contains(index) else { return nil }
            current = array[index]
        } else {
            return nil
        }
    }
    return current
}

enum JSONSearch {
    /// Finds every dictionary stored under `key`, anywhere in the tree, in document order.
    /// InnerTube nests results differently per endpoint and changes often, so parsers look
    /// for renderer objects by name instead of following one fixed path.
    static func collect(_ key: String, in node: Any, skipping: Set<String> = []) -> [[String: Any]] {
        var found: [[String: Any]] = []
        walk(node, key: key, skipping: skipping, into: &found)
        return found
    }

    private static func walk(_ node: Any, key: String, skipping: Set<String>, into found: inout [[String: Any]]) {
        if let dictionary = node as? [String: Any] {
            for (name, value) in dictionary {
                if skipping.contains(name) { continue }
                if name == key, let match = value as? [String: Any] {
                    found.append(match)
                } else {
                    walk(value, key: key, skipping: skipping, into: &found)
                }
            }
        } else if let array = node as? [Any] {
            for element in array {
                walk(element, key: key, skipping: skipping, into: &found)
            }
        }
    }
}
