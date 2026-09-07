import Foundation
import XCTest
import CursorUsageHTML
@testable import CursorUsageCore

enum SnapshotStore {
    static var update: Bool {
        let value = ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] ?? ""
        return ["1", "true", "yes"].contains(value.lowercased())
    }

    static var repositorySnapshots: URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0 ..< 6 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                let snapshots = directory.appendingPathComponent("Tests/CursorUsageTests/Snapshots")
                try? FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
                return snapshots
            }
            directory.deleteLastPathComponent()
        }
        let fallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/CursorUsageTests/Snapshots")
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}

enum SnapshotChrome {
    static func screenshot(html: String, name: String) throws -> Data {
        guard let chrome = chromeExecutable() else {
            throw XCTSkip("Chrome is required for visual snapshots. Set CHROME_PATH or install google-chrome.")
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-usage-snapshots-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let htmlFile = temp.appendingPathComponent("\(name).html")
        try html.write(to: htmlFile, atomically: true, encoding: .utf8)
        let rawPNG = temp.appendingPathComponent("raw.png")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: chrome)
        process.arguments = [
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--no-sandbox",
            "--user-data-dir=\(temp.appendingPathComponent("chrome").path)",
            "--window-size=760,1800",
            "--force-device-scale-factor=2",
            "--screenshot=\(rawPNG.path)",
            htmlFile.absoluteString,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: rawPNG.path) else {
            throw NSError(
                domain: "SnapshotChrome",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Chrome failed to screenshot \(name)"]
            )
        }

        let croppedPNG = temp.appendingPathComponent("cropped.png")
        if cropToContent(input: rawPNG, output: croppedPNG) {
            return try Data(contentsOf: croppedPNG)
        }
        return try Data(contentsOf: rawPNG)
    }

    /// Trim the headless Chrome viewport down to the menu card.
    private static func cropToContent(input: URL, output: URL) -> Bool {
        let script = """
        from pathlib import Path
        import sys
        try:
            from PIL import Image
        except ImportError:
            sys.exit(2)
        src, dest = Path(sys.argv[1]), Path(sys.argv[2])
        image = Image.open(src).convert('RGB')
        pixels = image.load()
        width, height = image.size
        background = pixels[0, 0]
        pad = 24
        left, top, right, bottom = width, height, 0, 0
        for y in range(height):
            for x in range(width):
                if pixels[x, y] != background:
                    left = min(left, x)
                    top = min(top, y)
                    right = max(right, x)
                    bottom = max(bottom, y)
        if right <= left or bottom <= top:
            sys.exit(3)
        box = (
            max(0, left - pad),
            max(0, top - pad),
            min(width, right + 1 + pad),
            min(height, bottom + 1 + pad),
        )
        image.crop(box).save(dest, 'PNG')
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, input.path, output.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: output.path)
        } catch {
            return false
        }
    }

    static func chromeExecutable() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["CHROME_PATH"],
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/usr/local/bin/google-chrome",
            "/usr/bin/chromium",
            "/usr/bin/chromium-browser",
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        ]
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
        let script = """
        from PIL import Image
        import sys

        colors = {
            "green": (0x34, 0xC7, 0x59),
            "yellow": (0xFF, 0xCC, 0x00),
            "orange": (0xFF, 0x9F, 0x0A),
            "red": (0xFF, 0x3B, 0x30),
        }

        def near(pixel, target, delta=20):
            return all(abs(pixel[i] - target[i]) <= delta for i in range(3))

        def counts(path):
            image = Image.open(path).convert("RGB")
            tallies = {name: 0 for name in colors}
            for pixel in image.getdata():
                for name, target in colors.items():
                    if near(pixel, target):
                        tallies[name] += 1
                        break
            return image.size, tallies

        gold_size, gold = counts(sys.argv[1])
        shot_size, shot = counts(sys.argv[2])
        if gold_size != shot_size:
            print(f"size mismatch gold={gold_size} actual={shot_size}")
            sys.exit(1)
        for name in colors:
            allowed = max(20, int(gold[name] * 0.05))
            if abs(gold[name] - shot[name]) > allowed:
                print(f"{name} bar pixels gold={gold[name]} actual={shot[name]}")
                sys.exit(1)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script, expected.path, actual.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .different("could not compare PNGs: \(error.localizedDescription)")
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus == 0 {
            return .same
        }
        return .different(output.isEmpty ? "images differ" : output)
    }
}
