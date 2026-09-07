import Foundation
import XCTest
import CursorUsageHTML
@testable import CursorUsageCore

enum SnapshotStore {
    static var update: Bool {
        envFlag("UPDATE_SNAPSHOTS")
    }

    static var skip: Bool {
        envFlag("SKIP_SNAPSHOT_TESTS")
    }

    static var repositoryRoot: URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 6 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    static var repositorySnapshots: URL {
        let snapshots = repositoryRoot.appendingPathComponent("Tests/CursorUsageTests/Snapshots")
        try? FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        return snapshots
    }

    static var pythonHelper: URL {
        if let bundled = Bundle.module.url(forResource: "snapshot_png", withExtension: "py") {
            return bundled
        }
        return repositoryRoot.appendingPathComponent("Tests/CursorUsageTests/snapshot_png.py")
    }

    private static func envFlag(_ name: String) -> Bool {
        ["1", "true", "yes"].contains((ProcessInfo.processInfo.environment[name] ?? "").lowercased())
    }
}

enum SnapshotChrome {
    static func screenshot(html: String, name: String) throws -> Data {
        guard let chrome = chromeExecutable() else {
            throw XCTSkip("Chrome is required for visual snapshots. Set CHROME_PATH or install google-chrome.")
        }
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: SnapshotStore.pythonHelper.path),
            "Missing \(SnapshotStore.pythonHelper.lastPathComponent)"
        )

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-usage-snapshots-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let htmlFile = temp.appendingPathComponent("\(name).html")
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)
        let croppedPNG = temp.appendingPathComponent("cropped.png")

        let result = runPython(["screenshot", chrome, htmlFile.path, croppedPNG.path])
        guard result.status == 0, FileManager.default.fileExists(atPath: croppedPNG.path) else {
            throw NSError(
                domain: "SnapshotChrome",
                code: Int(result.status),
                userInfo: [
                    NSLocalizedDescriptionKey: result.output.isEmpty
                        ? "Chrome failed to screenshot \(name)"
                        : result.output,
                ]
            )
        }
        return try Data(contentsOf: croppedPNG)
    }

    static func chromeExecutable() -> String? {
        var candidates = [
            ProcessInfo.processInfo.environment["CHROME_PATH"],
            "/opt/google/chrome/chrome",
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/local/bin/google-chrome",
            "/usr/bin/chromium",
            "/usr/bin/chromium-browser",
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                for name in ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome"] {
                    candidates.append("\(directory)/\(name)")
                }
            }
        }
        for candidate in candidates {
            if let candidate, FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

func assertPNGSnapshot(
    name: String,
    _ presentation: MenuPresentation,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let html = MenuHTMLRenderer.document(presentation, appearance: .light, title: name)
    let actual = try SnapshotChrome.screenshot(html: html, name: name)
    let destination = SnapshotStore.repositorySnapshots.appendingPathComponent("\(name).png")

    if SnapshotStore.update {
        try actual.write(to: destination, options: .atomic)
        return
    }

    guard FileManager.default.fileExists(atPath: destination.path) else {
        XCTFail("Missing PNG snapshot \(name).png. Re-run with UPDATE_SNAPSHOTS=1", file: file, line: line)
        return
    }

    let expected = try Data(contentsOf: destination)
    if actual == expected {
        return
    }

    let failed = SnapshotStore.repositorySnapshots.appendingPathComponent("\(name).actual.png")
    try actual.write(to: failed, options: .atomic)

    switch SnapshotCompare.layout(expected: destination, actual: failed) {
    case .same:
        try? FileManager.default.removeItem(at: failed)
        return
    case let .different(detail):
        XCTFail(
            "PNG snapshot mismatch for \(name): \(detail). Wrote \(failed.lastPathComponent). Re-run with UPDATE_SNAPSHOTS=1 if the change is intended.",
            file: file,
            line: line
        )
    }
}

enum SnapshotCompare {
    enum Result: Equatable {
        case same
        case different(String)
    }

    /// Chrome rasterizes fonts differently per machine. Bar fills use the
    /// exact theme hex colors, so those pixel counts stay stable.
    static func layout(expected: URL, actual: URL) -> Result {
        let result = runPython(["compare", expected.path, actual.path])
        if result.status == 0 {
            return .same
        }
        return .different(result.output.isEmpty ? "images differ" : result.output)
    }
}

private func runPython(_ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [SnapshotStore.pythonHelper.path] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        return (1, "could not run snapshot helper: \(error.localizedDescription)")
    }
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (process.terminationStatus, output)
}
