import Foundation

public struct CursorAuthOverrides: Sendable {
    public var stateDB: String?
    public var userDataDir: String?

    public init(stateDB: String? = nil, userDataDir: String? = nil) {
        self.stateDB = stateDB
        self.userDataDir = userDataDir
    }
}

public struct AuthDatabaseCandidate: Sendable {
    public let path: String
    public let source: String
    public let exists: Bool
}

public enum CursorAuthError: LocalizedError, Sendable {
    case noDatabaseFound(searched: [String])
    case tokenNotFound
    case invalidToken

    public var errorDescription: String? {
        switch self {
        case let .noDatabaseFound(searched):
            let paths = searched.isEmpty
                ? "(none)"
                : searched.map { "  - \($0)" }.joined(separator: "\n")
            return """
            No Cursor auth database found. Searched:
            \(paths)

            Set CURSOR_USER_DATA_DIR in .env (see .env.example), or export it in your shell.
            """
        case .tokenNotFound:
            return "Access token not found in Cursor database"
        case .invalidToken:
            return "Access token is not a valid JWT"
        }
    }
}

public struct CursorAuth: Sendable {
    public let databasePath: String
    public let token: String
    public let userId: String
    public let source: String

    public init(databasePath: String, token: String, userId: String, source: String) {
        self.databasePath = databasePath
        self.token = token
        self.userId = userId
        self.source = source
    }

    public var cookieHeaderValue: String {
        "WorkosCursorSessionToken=\(userId)%3A%3A\(token)"
    }

    public static func resolve(overrides: CursorAuthOverrides = CursorAuthOverrides()) throws -> CursorAuth {
        let candidates = CandidateDatabases.resolve(overrides: overrides)
        var searched: [String] = []

        for candidate in candidates {
            searched.append("\(candidate.path) (\(candidate.source))")
            guard FileManager.default.fileExists(atPath: candidate.path) else {
                continue
            }
            if let token = try? readToken(from: candidate.path), !token.isEmpty {
                let userId = try extractUserId(from: token)
                return CursorAuth(
                    databasePath: candidate.path,
                    token: token,
                    userId: userId,
                    source: candidate.source
                )
            }
        }

        throw CursorAuthError.noDatabaseFound(searched: searched)
    }

    static func listDatabaseCandidates(
        overrides: CursorAuthOverrides = CursorAuthOverrides()
    ) -> [AuthDatabaseCandidate] {
        CandidateDatabases.resolve(overrides: overrides).map { candidate in
            AuthDatabaseCandidate(
                path: candidate.path,
                source: candidate.source,
                exists: FileManager.default.fileExists(atPath: candidate.path)
            )
        }
    }

    private static func readToken(from path: String) throws -> String {
        let fileURI = fileURIForSQLite(path: path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            fileURI,
            "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken';",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let data: Data
        do {
            try process.run()
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        } catch {
            throw CursorAuthError.tokenNotFound
        }

        guard process.terminationStatus == 0 else {
            throw CursorAuthError.tokenNotFound
        }

        guard let raw = String(data: data, encoding: .utf8) else {
            throw CursorAuthError.tokenNotFound
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CursorAuthError.tokenNotFound
        }

        return stripJSONStringQuotes(trimmed)
    }

    private static func fileURIForSQLite(path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        return "file://\(encodedPath)?mode=ro&immutable=1"
    }

    private static func stripJSONStringQuotes(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("\""), result.hasSuffix("\""), result.count >= 2 {
            result = String(result.dropFirst().dropLast())
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractUserId(from token: String) throws -> String {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            throw CursorAuthError.invalidToken
        }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String
        else {
            throw CursorAuthError.invalidToken
        }

        guard let pipeIndex = subject.firstIndex(of: "|") else {
            throw CursorAuthError.invalidToken
        }

        let userId = String(subject[subject.index(after: pipeIndex)...])
        guard !userId.isEmpty else {
            throw CursorAuthError.invalidToken
        }

        return userId
    }
}

private struct CandidateDatabase {
    let path: String
    let source: String
}

private enum CandidateDatabases {
    static let stateDBRelativePath = "User/globalStorage/state.vscdb"
    static let userDataDirKey = "CURSOR_USER_DATA_DIR"
    static let stateDBKey = "CURSOR_STATE_DB"

    static func resolve(overrides: CursorAuthOverrides = CursorAuthOverrides()) -> [CandidateDatabase] {
        var candidates: [CandidateDatabase] = []
        var seen = Set<String>()

        func append(path: String, source: String) {
            let normalized = (path as NSString).standardizingPath
            guard seen.insert(normalized).inserted else { return }
            candidates.append(CandidateDatabase(path: normalized, source: source))
        }

        let fileConfig = DotEnv.load()
        let processEnv = ProcessInfo.processInfo.environment

        if let stateDB = firstNonEmpty(overrides.stateDB) {
            append(path: stateDB, source: "override state db")
        }

        if let stateDB = firstNonEmpty(processEnv[stateDBKey], fileConfig[stateDBKey]) {
            append(path: stateDB, source: "\(stateDBKey)")
        }

        if let userDataDir = firstNonEmpty(overrides.userDataDir) {
            append(
                path: (userDataDir as NSString).appendingPathComponent(stateDBRelativePath),
                source: "override user data dir"
            )
        }

        if let userDataDir = firstNonEmpty(processEnv[userDataDirKey], fileConfig[userDataDirKey]) {
            append(
                path: (userDataDir as NSString).appendingPathComponent(stateDBRelativePath),
                source: "\(userDataDirKey)"
            )
        }

        for dir in RunningCursorUserDataDirs.discover() {
            append(
                path: (dir as NSString).appendingPathComponent(stateDBRelativePath),
                source: "running Cursor --user-data-dir"
            )
        }

        let defaultDir = defaultUserDataDir()
        append(
            path: (defaultDir as NSString).appendingPathComponent(stateDBRelativePath),
            source: "default Application Support"
        )

        return candidates
    }

    private static func defaultUserDataDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return (home as NSString).appendingPathComponent("Library/Application Support/Cursor")
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }
}

private enum DotEnv {
    static func load() -> [String: String] {
        guard let envPath = findEnvFile() else {
            return [:]
        }

        guard let contents = try? String(contentsOfFile: envPath, encoding: .utf8) else {
            return [:]
        }

        var values: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            guard let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\""))
                || (value.hasPrefix("'") && value.hasSuffix("'")),
                value.count >= 2
            {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }

        return values
    }

    private static func findEnvFile() -> String? {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        // Preferred for the packaged .app (Finder launch has a useless cwd).
        candidates.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CursorUsage/.env")
        )

        // Next to the .app bundle: CursorUsage.app/../.env
        if let executable = Bundle.main.executableURL {
            let macosDir = executable.deletingLastPathComponent()
            let contentsDir = macosDir.deletingLastPathComponent()
            let appBundle = contentsDir.deletingLastPathComponent()
            candidates.append(appBundle.deletingLastPathComponent().appendingPathComponent(".env"))
            candidates.append(macosDir.appendingPathComponent(".env"))
        }

        candidates.append(
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".env")
        )

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate.path
        }

        // swift run: walk up from cwd / binary looking for Package.swift + .env
        var searchRoots: [URL] = [
            URL(fileURLWithPath: fileManager.currentDirectoryPath),
        ]
        if let executableDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            searchRoots.append(executableDir)
        }

        for start in searchRoots {
            var directory = start
            for _ in 0 ..< 8 {
                let envFile = directory.appendingPathComponent(".env")
                let packageFile = directory.appendingPathComponent("Package.swift")
                if fileManager.fileExists(atPath: envFile.path),
                   fileManager.fileExists(atPath: packageFile.path)
                {
                    return envFile.path
                }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path {
                    break
                }
                directory = parent
            }
        }

        return nil
    }
}

private enum RunningCursorUserDataDirs {
    static func discover() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "args="]

        let pipe = Pipe()
        process.standardOutput = pipe
        // Discard stderr so a full stderr pipe cannot stall the child.
        process.standardError = FileHandle.nullDevice

        let data: Data
        do {
            try process.run()
            // Drain stdout before waitUntilExit. `ps -ax -o args=` can exceed the
            // pipe buffer; waiting first deadlocks (child blocked on write, parent
            // blocked on wait).
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard process.terminationStatus == 0 else {
            return []
        }

        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        var dirs: [String] = []
        var seen = Set<String>()

        for line in output.split(separator: "\n") {
            guard line.contains("Cursor"),
                  let dir = extractUserDataDir(from: String(line))
            else {
                continue
            }

            let normalized = (dir as NSString).standardizingPath
            guard seen.insert(normalized).inserted else { continue }
            dirs.append(normalized)
        }

        // Prefer the profile whose DB was written most recently (likely the active account).
        return dirs.sorted { lhs, rhs in
            modificationDate(forUserDataDir: lhs) > modificationDate(forUserDataDir: rhs)
        }
    }

    private static func extractUserDataDir(from args: String) -> String? {
        let marker = "--user-data-dir="
        guard let range = args.range(of: marker) else {
            return nil
        }

        let after = args[range.upperBound...]
        if after.hasPrefix("\"") {
            let withoutOpen = after.dropFirst()
            guard let end = withoutOpen.firstIndex(of: "\"") else {
                return nil
            }
            return String(withoutOpen[..<end])
        }

        var value = ""
        for character in after {
            if character.isWhitespace {
                break
            }
            value.append(character)
        }
        return value.isEmpty ? nil : value
    }

    private static func modificationDate(forUserDataDir dir: String) -> Date {
        let dbPath = (dir as NSString).appendingPathComponent(CandidateDatabases.stateDBRelativePath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath)
        return (attrs?[.modificationDate] as? Date) ?? .distantPast
    }
}
