import Foundation

struct CodeownersParser: Sendable {
    struct Rule: Sendable {
        let pattern: String
        let owners: [String]  // @username or @org/team
        let isCatchAll: Bool
    }

    let rules: [Rule]

    init(content: String) {
        var parsed: [Rule] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }

            let pattern = parts[0]
            let owners = Array(parts[1...])
            let isCatchAll = Self.isCatchAllPattern(pattern)
            parsed.append(Rule(pattern: pattern, owners: owners, isCatchAll: isCatchAll))
        }
        self.rules = parsed
    }

    /// Find owners for a file path. Returns the last matching rule's owners (CODEOWNERS uses last-match-wins).
    func owners(for filePath: String) -> (owners: [String], isCatchAll: Bool) {
        var lastMatch: Rule?
        for rule in rules {
            if Self.matches(pattern: rule.pattern, filePath: filePath) {
                lastMatch = rule
            }
        }
        guard let match = lastMatch else {
            return ([], false)
        }
        return (match.owners, match.isCatchAll)
    }

    /// Check if a user is a direct (non-catch-all) owner of any of the given files.
    func isDirectOwner(username: String, files: [String]) -> Bool {
        let needle = "@\(username)"
        for file in files {
            let (owners, isCatchAll) = self.owners(for: file)
            if !isCatchAll && owners.contains(where: { $0.caseInsensitiveCompare(needle) == .orderedSame }) {
                return true
            }
        }
        return false
    }

    // MARK: - Pattern classification

    static func isCatchAllPattern(_ pattern: String) -> Bool {
        // Catch-all: *, /*, or very broad patterns
        let p = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return p == "*" || p == "**" || p == "**/*"
    }

    // MARK: - Pattern matching (simplified gitignore-style)

    static func matches(pattern: String, filePath: String) -> Bool {
        let path = filePath.hasPrefix("/") ? String(filePath.dropFirst()) : filePath

        // Exact file match
        let cleanPattern = pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern

        // * or ** at root matches everything
        if cleanPattern == "*" || cleanPattern == "**" || cleanPattern == "**/*" {
            return true
        }

        // Extension pattern: *.ext — matches files with this extension anywhere
        if cleanPattern.hasPrefix("*.") {
            let ext = String(cleanPattern.dropFirst(2))
            return path.hasSuffix(".\(ext)")
        }

        // **/*.ext — matches extension anywhere
        if cleanPattern.hasPrefix("**/") {
            let rest = String(cleanPattern.dropFirst(3))
            if rest.hasPrefix("*.") {
                let ext = String(rest.dropFirst(2))
                return path.hasSuffix(".\(ext)")
            }
            // **/filename — matches filename anywhere in tree
            return path.hasSuffix("/\(rest)") || path == rest || path.contains("/\(rest)/")
        }

        // Directory pattern: path/ — matches anything under that directory
        if cleanPattern.hasSuffix("/") {
            let dir = String(cleanPattern.dropLast())
            return path.hasPrefix(dir + "/") || path == dir
        }

        // Directory pattern without trailing slash but with wildcard: path/*
        if cleanPattern.hasSuffix("/*") {
            let dir = String(cleanPattern.dropLast(2))
            return path.hasPrefix(dir + "/")
        }

        // Directory pattern: path/**
        if cleanPattern.hasSuffix("/**") {
            let dir = String(cleanPattern.dropLast(3))
            return path.hasPrefix(dir + "/")
        }

        // Exact match
        if path == cleanPattern {
            return true
        }

        // Treat pattern as a directory prefix if it doesn't contain wildcards or extensions
        if !cleanPattern.contains("*") && !cleanPattern.contains(".") {
            return path.hasPrefix(cleanPattern + "/")
        }

        // Treat as directory prefix even with dots (e.g. "src/com.example")
        if !cleanPattern.contains("*") {
            return path == cleanPattern || path.hasPrefix(cleanPattern + "/")
        }

        return false
    }
}
