import Foundation

public struct CursorProfile: Equatable, Sendable {
    public var databasePath: String
    public var title: String
    public var source: String
    public var userId: String

    public init(databasePath: String, title: String, source: String, userId: String) {
        self.databasePath = databasePath
        self.title = title
        self.source = source
        self.userId = userId
    }

    /// One row per signed-in account. Named user-data-dirs win over Default.
    static func uniqueAccounts(_ profiles: [CursorProfile]) -> [CursorProfile] {
        var chosen: [String: CursorProfile] = [:]
        var order: [String] = []

        for profile in profiles {
            if chosen[profile.userId] == nil {
                order.append(profile.userId)
                chosen[profile.userId] = profile
                continue
            }
            if shouldReplace(chosen[profile.userId]!, with: profile) {
                chosen[profile.userId] = profile
            }
        }

        return order.compactMap { chosen[$0] }
    }

    private static func shouldReplace(_ current: CursorProfile, with candidate: CursorProfile) -> Bool {
        isDefaultAccountHome(current) && !isDefaultAccountHome(candidate)
    }

    static func isDefaultAccountHome(_ profile: CursorProfile) -> Bool {
        let directory = CursorProfileLabel.userDataDir(fromDatabasePath: profile.databasePath)
        return CursorProfileLabel.rawTitle(forUserDataDir: directory) == "Default"
    }
}

public struct CursorProfileOption: Equatable, Sendable {
    public var id: String
    public var title: String
    public var userId: String
    public var isSelected: Bool

    public init(id: String, title: String, userId: String = "", isSelected: Bool) {
        self.id = id
        self.title = title
        self.userId = userId
        self.isSelected = isSelected
    }
}

enum CursorStateDatabase {
    static let relativePath = "User/globalStorage/state.vscdb"
}

enum CursorProfileLabel {
    static func uniqueTitles(forDatabasePaths paths: [String]) -> [String] {
        let directories = paths.map(userDataDir(fromDatabasePath:))
        let rawTitles = directories.map(rawTitle(forUserDataDir:))
        var counts: [String: Int] = [:]
        for title in rawTitles {
            counts[title, default: 0] += 1
        }
        return zip(directories, rawTitles).map { directory, title in
            if counts[title, default: 0] <= 1 {
                return title
            }
            return disambiguatedTitle(userDataDir: directory, rawTitle: title)
        }
    }

    static func userDataDir(fromDatabasePath path: String) -> String {
        var url = URL(fileURLWithPath: path)
        if url.lastPathComponent == "state.vscdb" {
            url.deleteLastPathComponent()
            if url.lastPathComponent == "globalStorage" {
                url.deleteLastPathComponent()
                if url.lastPathComponent == "User" {
                    url.deleteLastPathComponent()
                    return url.path
                }
            }
        }
        return url.deletingLastPathComponent().path
    }

    static func rawTitle(forUserDataDir dir: String) -> String {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        if name == "Cursor", parent == "Application Support" {
            return "Default"
        }
        return name.isEmpty ? dir : name
    }

    private static func disambiguatedTitle(userDataDir dir: String, rawTitle: String) -> String {
        let parent = URL(fileURLWithPath: dir, isDirectory: true)
            .deletingLastPathComponent()
            .lastPathComponent
        if parent.isEmpty {
            return rawTitle
        }
        return "\(parent)/\(rawTitle)"
    }
}

enum CursorProfileDiscovery {
    static func userDataDirs(inApplicationSupport applicationSupport: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: applicationSupport) else {
            return []
        }

        return names.compactMap { name -> String? in
            guard name.hasPrefix("Cursor"), name != "CursorUsage" else {
                return nil
            }
            let directory = (applicationSupport as NSString).appendingPathComponent(name)
            let database = (directory as NSString).appendingPathComponent(CursorStateDatabase.relativePath)
            guard FileManager.default.fileExists(atPath: database) else {
                return nil
            }
            return (directory as NSString).standardizingPath
        }
        .sorted()
    }

    static func applicationSupportDirectory() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .path
    }
}
