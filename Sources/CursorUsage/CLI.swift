import Foundation

struct CLIInvocation: Equatable {
    enum Command: String {
        case gui
        case help
        case version
        case check
        case auth
        case selfTest
    }

    enum Format: String {
        case text
        case json
    }

    var command: Command = .gui
    var format: Format = .text
    var compact: Bool = false
    var stateDB: String?
    var userDataDir: String?
    var programName: String = AppInfo.name
}

enum CLIParseError: LocalizedError {
    case unknownOption(String)
    case missingValue(String)
    case invalidFormat(String)
    case unexpectedArgument(String)

    var errorDescription: String? {
        switch self {
        case let .unknownOption(option):
            return "Unknown option: \(option)"
        case let .missingValue(option):
            return "Missing value for \(option)"
        case let .invalidFormat(value):
            return "Invalid format '\(value)'. Use text or json."
        case let .unexpectedArgument(argument):
            return "Unexpected argument: \(argument)"
        }
    }
}

enum CLIDispatch {
    case runGUI
    case finished(Int32)
}

enum CLI {
    static func dispatch(arguments: [String]) -> CLIDispatch {
        switch parse(arguments) {
        case let .failure(error):
            let program = programName(from: arguments)
            fputs("Error: \(error.localizedDescription)\n", stderr)
            fputs("Try `\(program) --help` or `\(program) --help --json`.\n", stderr)
            return .finished(2)
        case let .success(invocation):
            switch invocation.command {
            case .gui:
                return .runGUI
            case .help, .version, .check, .auth, .selfTest:
                return .finished(run(invocation))
            }
        }
    }

    static func parse(_ arguments: [String]) -> Result<CLIInvocation, CLIParseError> {
        var invocation = CLIInvocation()
        invocation.programName = programName(from: arguments)

        var wantsHelp = false
        var wantsVersion = false
        var wantsCheck = false
        var wantsAuth = false
        var wantsSelfTest = false
        var sawJSON = false
        var sawFormat = false

        let args = Array(arguments.dropFirst())
        var index = 0
        var endOfOptions = false

        while index < args.count {
            let arg = args[index]

            if endOfOptions {
                if let error = applyPositional(
                    arg,
                    wantsHelp: &wantsHelp,
                    wantsVersion: &wantsVersion,
                    wantsCheck: &wantsCheck,
                    wantsAuth: &wantsAuth,
                    wantsSelfTest: &wantsSelfTest
                ) {
                    return .failure(error)
                }
                index += 1
                continue
            }

            if arg == "--" {
                endOfOptions = true
                index += 1
                continue
            }

            if arg == "-h" || arg == "--help" {
                wantsHelp = true
                index += 1
                continue
            }
            if arg == "-V" || arg == "--version" {
                wantsVersion = true
                index += 1
                continue
            }
            if arg == "--check" {
                wantsCheck = true
                index += 1
                continue
            }
            if arg == "--auth" {
                wantsAuth = true
                index += 1
                continue
            }
            if arg == "--self-test" {
                wantsSelfTest = true
                index += 1
                continue
            }
            if arg == "--compact" {
                invocation.compact = true
                index += 1
                continue
            }
            if arg == "--json" {
                invocation.format = .json
                sawJSON = true
                index += 1
                continue
            }
            if arg == "--format" {
                guard index + 1 < args.count else {
                    return .failure(.missingValue("--format"))
                }
                switch args[index + 1].lowercased() {
                case "text":
                    invocation.format = .text
                case "json":
                    invocation.format = .json
                    sawJSON = true
                default:
                    return .failure(.invalidFormat(args[index + 1]))
                }
                sawFormat = true
                index += 2
                continue
            }
            if arg.hasPrefix("--format=") {
                let value = String(arg.dropFirst("--format=".count))
                switch value.lowercased() {
                case "text":
                    invocation.format = .text
                case "json":
                    invocation.format = .json
                    sawJSON = true
                default:
                    return .failure(.invalidFormat(value))
                }
                sawFormat = true
                index += 1
                continue
            }
            if arg == "--state-db" {
                guard index + 1 < args.count else {
                    return .failure(.missingValue("--state-db"))
                }
                invocation.stateDB = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("--state-db=") {
                invocation.stateDB = String(arg.dropFirst("--state-db=".count))
                index += 1
                continue
            }
            if arg == "--user-data-dir" {
                guard index + 1 < args.count else {
                    return .failure(.missingValue("--user-data-dir"))
                }
                invocation.userDataDir = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("--user-data-dir=") {
                invocation.userDataDir = String(arg.dropFirst("--user-data-dir=".count))
                index += 1
                continue
            }
            if arg.hasPrefix("-") {
                return .failure(.unknownOption(arg))
            }
            if let error = applyPositional(
                arg,
                wantsHelp: &wantsHelp,
                wantsVersion: &wantsVersion,
                wantsCheck: &wantsCheck,
                wantsAuth: &wantsAuth,
                wantsSelfTest: &wantsSelfTest
            ) {
                return .failure(error)
            }
            index += 1
        }

        if wantsHelp {
            invocation.command = .help
        } else if wantsVersion {
            invocation.command = .version
        } else if wantsSelfTest {
            invocation.command = .selfTest
        } else if wantsCheck
                    || (invocation.compact && !wantsAuth)
                    || (sawJSON && !wantsAuth)
                    || (sawFormat && !wantsAuth)
        {
            invocation.command = .check
        } else if wantsAuth {
            invocation.command = .auth
        } else {
            invocation.command = .gui
        }

        if invocation.command == .gui, invocation.format == .json {
            invocation.command = .check
        }

        return .success(invocation)
    }

    static func run(_ invocation: CLIInvocation) -> Int32 {
        switch invocation.command {
        case .gui:
            return 0
        case .help:
            return runHelp(invocation)
        case .version:
            return runVersion(invocation)
        case .auth:
            return runAuth(invocation)
        case .check:
            return runCheck(invocation)
        case .selfTest:
            return runSelfTest(invocation)
        }
    }

    private static func applyPositional(
        _ arg: String,
        wantsHelp: inout Bool,
        wantsVersion: inout Bool,
        wantsCheck: inout Bool,
        wantsAuth: inout Bool,
        wantsSelfTest: inout Bool
    ) -> CLIParseError? {
        switch arg {
        case "help":
            wantsHelp = true
            return nil
        case "version":
            wantsVersion = true
            return nil
        case "check":
            wantsCheck = true
            return nil
        case "auth":
            wantsAuth = true
            return nil
        case "self-test":
            wantsSelfTest = true
            return nil
        default:
            return .unexpectedArgument(arg)
        }
    }

    private static func programName(from arguments: [String]) -> String {
        guard let first = arguments.first else { return AppInfo.name }
        return URL(fileURLWithPath: first).lastPathComponent
    }

    private static func overrides(from invocation: CLIInvocation) -> CursorAuthOverrides {
        CursorAuthOverrides(stateDB: invocation.stateDB, userDataDir: invocation.userDataDir)
    }

    private static func runHelp(_ invocation: CLIInvocation) -> Int32 {
        if invocation.format == .json {
            do {
                print(try UsageReport.encodeJSON(CLIHelpDocument.make(programName: invocation.programName)), terminator: "")
                return 0
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                return 1
            }
        }
        print(CLIHelpDocument.plainText(programName: invocation.programName))
        return 0
    }

    private static func runVersion(_ invocation: CLIInvocation) -> Int32 {
        if invocation.format == .json {
            let document = VersionJSONDocument(
                schemaVersion: AppInfo.schemaVersion,
                name: AppInfo.name,
                displayName: AppInfo.displayName,
                version: AppInfo.version
            )
            do {
                print(try UsageReport.encodeJSON(document), terminator: "")
                return 0
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                return 1
            }
        }
        print("\(AppInfo.name) \(AppInfo.version)")
        return 0
    }

    private static func runAuth(_ invocation: CLIInvocation) -> Int32 {
        let overrides = overrides(from: invocation)
        let candidates = CursorAuth.listDatabaseCandidates(overrides: overrides)
        do {
            let auth = try CursorAuth.resolve(overrides: overrides)
            if invocation.format == .json {
                let document = AuthJSONDocument.make(ok: true, auth: auth, candidates: candidates, error: nil)
                print(try UsageReport.encodeJSON(document), terminator: "")
            } else {
                print(authText(auth: auth, candidates: candidates))
            }
            return 0
        } catch {
            if invocation.format == .json {
                let document = AuthJSONDocument.make(ok: false, auth: nil, candidates: candidates, error: error.localizedDescription)
                if let encoded = try? UsageReport.encodeJSON(document) {
                    print(encoded, terminator: "")
                } else {
                    fputs("Error: \(error.localizedDescription)\n", stderr)
                }
            } else {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                fputs("\n\(candidateText(candidates))\n", stderr)
            }
            return 1
        }
    }

    private static func runCheck(_ invocation: CLIInvocation) -> Int32 {
        let overrides = overrides(from: invocation)
        do {
            let auth = try CursorAuth.resolve(overrides: overrides)
            let api = CursorAPI(auth: auth, overrides: overrides)
            let state = try runBlocking { try await UsageSnapshotFetcher.fetchDisplayState(using: api) }

            switch UsageScreen.make(
                from: state,
                includePollingHint: false,
                missingBreakdownMessage: "Breakdown unavailable"
            ) {
            case let .unauthenticated(message):
                return emitCheckFailure(invocation, message: message, auth: auth)
            case .loading:
                return emitCheckFailure(invocation, message: "No usage summary returned", auth: auth)
            case let .ready(model):
                if invocation.format == .json {
                    print(try UsageReport.json(model: model, auth: auth), terminator: "")
                } else {
                    print(UsageReport.text(model: model, auth: auth, compact: invocation.compact))
                }
                return 0
            }
        } catch {
            return emitCheckFailure(invocation, message: error.localizedDescription, auth: nil)
        }
    }

    private static func emitCheckFailure(
        _ invocation: CLIInvocation,
        message: String,
        auth: CursorAuth?
    ) -> Int32 {
        if invocation.format == .json {
            let document = CheckFailureJSONDocument(
                schemaVersion: AppInfo.schemaVersion,
                ok: false,
                version: AppInfo.version,
                error: message,
                dashboardURL: AppInfo.dashboardURL,
                auth: auth.map {
                    CheckFailureJSONDocument.Auth(
                        databasePath: $0.databasePath,
                        source: $0.source,
                        userId: $0.userId
                    )
                }
            )
            if let encoded = try? UsageReport.encodeJSON(document) {
                print(encoded, terminator: "")
            } else {
                fputs("Error: \(message)\n", stderr)
            }
        } else {
            fputs("Error: \(message)\n", stderr)
        }
        return 1
    }

    private static func authText(auth: CursorAuth, candidates: [AuthDatabaseCandidate]) -> String {
        var lines: [String] = []
        lines.append("Database: \(auth.databasePath)")
        lines.append("Resolved via: \(auth.source)")
        lines.append("User ID: \(auth.userId)")
        lines.append("")
        lines.append(candidateText(candidates, selectedPath: auth.databasePath))
        return lines.joined(separator: "\n")
    }

    private static func candidateText(
        _ candidates: [AuthDatabaseCandidate],
        selectedPath: String? = nil
    ) -> String {
        var lines: [String] = ["Candidates (search order):"]
        if candidates.isEmpty {
            lines.append("  (none)")
            return lines.joined(separator: "\n")
        }
        for candidate in candidates {
            let marker = candidate.path == selectedPath ? "*" : " "
            let existence = candidate.exists ? "exists" : "missing"
            lines.append("\(marker) \(candidate.path)")
            lines.append("    source: \(candidate.source) [\(existence)]")
        }
        return lines.joined(separator: "\n")
    }

    static func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?

        Task {
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()

        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        case .none:
            throw CursorAPIError.invalidURL
        }
    }

    private static func runSelfTest(_ invocation: CLIInvocation) -> Int32 {
        var failures: [String] = []
        var passed = 0

        func expectSuccess(
            _ args: [String],
            command: CLIInvocation.Command,
            format: CLIInvocation.Format = .text,
            compact: Bool = false,
            stateDB: String? = nil,
            userDataDir: String? = nil
        ) {
            switch parse(["CursorUsage"] + args) {
            case let .failure(error):
                failures.append("\(args) expected \(command.rawValue), got error: \(error.localizedDescription)")
            case let .success(parsed):
                if parsed.command != command
                    || parsed.format != format
                    || parsed.compact != compact
                    || parsed.stateDB != stateDB
                    || parsed.userDataDir != userDataDir
                {
                    failures.append(
                        "\(args) expected command=\(command.rawValue) format=\(format.rawValue) compact=\(compact) stateDB=\(stateDB ?? "nil") userDataDir=\(userDataDir ?? "nil"), got command=\(parsed.command.rawValue) format=\(parsed.format.rawValue) compact=\(parsed.compact) stateDB=\(parsed.stateDB ?? "nil") userDataDir=\(parsed.userDataDir ?? "nil")"
                    )
                } else {
                    passed += 1
                }
            }
        }

        func expectFailure(_ args: [String]) {
            switch parse(["CursorUsage"] + args) {
            case .failure:
                passed += 1
            case let .success(parsed):
                failures.append("\(args) expected parse error, got \(parsed.command.rawValue)")
            }
        }

        expectSuccess([], command: .gui)
        expectSuccess(["--help"], command: .help)
        expectSuccess(["-h"], command: .help)
        expectSuccess(["help"], command: .help)
        expectSuccess(["--help", "--json"], command: .help, format: .json)
        expectSuccess(["--version"], command: .version)
        expectSuccess(["-V", "--json"], command: .version, format: .json)
        expectSuccess(["--check"], command: .check)
        expectSuccess(["check"], command: .check)
        expectSuccess(["--help", "--format", "json"], command: .help, format: .json)
        expectSuccess(["--format", "text"], command: .check)
        expectSuccess(["--json"], command: .check, format: .json)
        expectSuccess(["--check", "--json"], command: .check, format: .json)
        expectSuccess(["--format", "json"], command: .check, format: .json)
        expectSuccess(["--format=json"], command: .check, format: .json)
        expectSuccess(["--compact"], command: .check, compact: true)
        expectSuccess(["--check", "--compact"], command: .check, compact: true)
        expectSuccess(["--auth"], command: .auth)
        expectSuccess(["auth"], command: .auth)
        expectSuccess(["--auth", "--json"], command: .auth, format: .json)
        expectSuccess(["--auth", "--compact"], command: .auth, compact: true)
        expectSuccess(["--self-test"], command: .selfTest)
        expectSuccess(["--self-test", "--json"], command: .selfTest, format: .json)
        expectSuccess(["--state-db", "/tmp/state.vscdb", "--check"], command: .check, stateDB: "/tmp/state.vscdb")
        expectSuccess(
            ["--user-data-dir=/tmp/cursor-profile", "--check"],
            command: .check,
            userDataDir: "/tmp/cursor-profile"
        )
        expectFailure(["--unknown"])
        expectFailure(["--format"])
        expectFailure(["--format", "yaml"])
        expectFailure(["--state-db"])
        expectFailure(["--user-data-dir"])
        expectFailure(["--check", "nope"])

        let total = passed + failures.count
        if invocation.format == .json {
            let document = SelfTestJSONDocument(
                schemaVersion: AppInfo.schemaVersion,
                ok: failures.isEmpty,
                version: AppInfo.version,
                passed: passed,
                failed: failures.count,
                total: total,
                failures: failures
            )
            if let encoded = try? UsageReport.encodeJSON(document) {
                print(encoded, terminator: "")
            }
        } else if failures.isEmpty {
            print("self-test: \(passed)/\(total) passed")
        } else {
            fputs("self-test: \(passed)/\(total) passed, \(failures.count) failed\n", stderr)
            for failure in failures {
                fputs("  - \(failure)\n", stderr)
            }
        }
        return failures.isEmpty ? 0 : 1
    }
}

struct SelfTestJSONDocument: Encodable {
    let schemaVersion: Int
    let ok: Bool
    let version: String
    let passed: Int
    let failed: Int
    let total: Int
    let failures: [String]
}

struct VersionJSONDocument: Encodable {
    let schemaVersion: Int
    let name: String
    let displayName: String
    let version: String
}

struct CheckFailureJSONDocument: Encodable {
    struct Auth: Encodable {
        let databasePath: String
        let source: String
        let userId: String
    }

    let schemaVersion: Int
    let ok: Bool
    let version: String
    let error: String
    let dashboardURL: String
    let auth: Auth?
}

struct AuthJSONDocument: Encodable {
    struct Auth: Encodable {
        let databasePath: String
        let source: String
        let userId: String
    }

    struct Candidate: Encodable {
        let path: String
        let source: String
        let exists: Bool
        let selected: Bool
    }

    let schemaVersion: Int
    let ok: Bool
    let version: String
    let error: String?
    let auth: Auth?
    let candidates: [Candidate]

    static func make(
        ok: Bool,
        auth: CursorAuth?,
        candidates: [AuthDatabaseCandidate],
        error: String?
    ) -> AuthJSONDocument {
        AuthJSONDocument(
            schemaVersion: AppInfo.schemaVersion,
            ok: ok,
            version: AppInfo.version,
            error: error,
            auth: auth.map { Auth(databasePath: $0.databasePath, source: $0.source, userId: $0.userId) },
            candidates: candidates.map { candidate in
                Candidate(
                    path: candidate.path,
                    source: candidate.source,
                    exists: candidate.exists,
                    selected: candidate.path == auth?.databasePath
                )
            }
        )
    }
}

struct CLIHelpDocument: Encodable {
    struct Flag: Encodable {
        let names: [String]
        let summary: String
        let value: String?
    }

    struct EnvVar: Encodable {
        let name: String
        let summary: String
    }

    struct ExitCode: Encodable {
        let code: Int
        let meaning: String
    }

    struct Example: Encodable {
        let command: String
        let summary: String
    }

    let schemaVersion: Int
    let name: String
    let displayName: String
    let version: String
    let summary: String
    let usage: [String]
    let defaultMode: String
    let commands: [Flag]
    let options: [Flag]
    let environment: [EnvVar]
    let envFileSearchOrder: [String]
    let exitCodes: [ExitCode]
    let examples: [Example]
    let checkJson: String
    let notes: [String]

    static func make(programName: String) -> CLIHelpDocument {
        CLIHelpDocument(
            schemaVersion: AppInfo.schemaVersion,
            name: AppInfo.name,
            displayName: AppInfo.displayName,
            version: AppInfo.version,
            summary: "Live Cursor AI usage for the current billing cycle. Default (no args) launches the macOS menu bar extra. Pass --check for the same data on stdout.",
            usage: [
                "\(programName) [command] [options]",
                "\(programName) --help",
                "\(programName) --check [--json] [--compact]",
                "swift run CursorUsage -- --help",
            ],
            defaultMode: "gui",
            commands: [
                Flag(names: ["(no args)"], summary: "Launch the macOS menu bar extra.", value: nil),
                Flag(names: ["--help", "-h", "help"], summary: "Show this help. Add --json for a machine-readable command catalog.", value: nil),
                Flag(names: ["--version", "-V", "version"], summary: "Print the version.", value: nil),
                Flag(names: ["--check", "check"], summary: "One-shot usage report matching the menu bar dropdown (no GUI).", value: nil),
                Flag(names: ["--auth", "auth"], summary: "Resolve the Cursor session database only; do not call the API.", value: nil),
                Flag(names: ["--self-test", "self-test"], summary: "Parse-argument checks only (no network, no GUI).", value: nil),
            ],
            options: [
                Flag(names: ["--json"], summary: "Shortcut for --format json. With no other command, implies --check.", value: nil),
                Flag(names: ["--format"], summary: "Output format for --help, --version, --check, and --auth.", value: "text|json"),
                Flag(names: ["--compact"], summary: "Text --check prints only the menu-bar line. Ignored for --json, which always includes the full report.", value: nil),
                Flag(names: ["--state-db"], summary: "Path to Cursor state.vscdb. Tried before CURSOR_STATE_DB.", value: "PATH"),
                Flag(names: ["--user-data-dir"], summary: "Cursor user-data directory. Tried before CURSOR_USER_DATA_DIR.", value: "PATH"),
            ],
            environment: [
                EnvVar(name: "CURSOR_STATE_DB", summary: "Direct path to User/globalStorage/state.vscdb."),
                EnvVar(name: "CURSOR_USER_DATA_DIR", summary: "Cursor user-data dir; state.vscdb is appended as User/globalStorage/state.vscdb."),
            ],
            envFileSearchOrder: [
                "~/Library/Application Support/CursorUsage/.env",
                ".env next to CursorUsage.app",
                ".env in the current directory",
                "Package.swift directory when developing with swift run",
            ],
            exitCodes: [
                ExitCode(code: 0, meaning: "Success"),
                ExitCode(code: 1, meaning: "Auth or API error"),
                ExitCode(code: 2, meaning: "Invalid arguments"),
            ],
            examples: [
                Example(command: "\(programName) --help --json", summary: "Agent-oriented command catalog."),
                Example(command: "\(programName) --check", summary: "Human-readable report matching the dropdown."),
                Example(command: "\(programName) --check --json", summary: "Stable JSON for the same report (schemaVersion \(AppInfo.schemaVersion))."),
                Example(command: "\(programName) --compact", summary: "One line, as shown in the menu bar."),
                Example(command: "\(programName) --auth --json", summary: "Show which SQLite database supplied the session."),
                Example(command: "\(programName) --self-test", summary: "Verify CLI argument parsing (no network)."),
                Example(command: "swift run CursorUsage -- --check --json", summary: "Pass flags through SwiftPM with --."),
            ],
            checkJson: "Check JSON includes schemaVersion, ok, menubar, membershipType, billingCycle, percent, total, sections (cursor/api/bot with meter captions, barFraction, meterLevel, models), billing, dashboardURL, and auth. Failures use ok=false and error.",
            notes: [
                "--check uses the same UsageViewModel as the menu: membership, cycle, total pool, Cursor/API/Bot meters, per-model rows, plan limit, weekly bot window, and on-demand billing.",
                "GUI-only behavior: 30s/120s polling, percent-up arrows, and native colored bars. CLI renders the same meters as ASCII and meterLevel.",
                "Never prints the session token. User ID is the JWT subject suffix used in the API cookie.",
                "Unknown flags exit 2 instead of launching the menu bar extra.",
                "When using `swift run`, put `--` before tool flags so SwiftPM does not swallow --help / --json.",
            ]
        )
    }

    static func plainText(programName: String) -> String {
        let doc = make(programName: programName)
        var lines: [String] = []
        lines.append("\(doc.displayName) \(doc.version) — \(doc.summary)")
        lines.append("")
        lines.append("USAGE")
        for usage in doc.usage {
            lines.append("  \(usage)")
        }
        lines.append("")
        lines.append("COMMANDS")
        for command in doc.commands {
            lines.append(contentsOf: flagLines(command))
        }
        lines.append("")
        lines.append("OPTIONS")
        for option in doc.options {
            lines.append(contentsOf: flagLines(option))
        }
        lines.append("")
        lines.append("ENVIRONMENT")
        for env in doc.environment {
            lines.append("  \(env.name)")
            lines.append("      \(env.summary)")
        }
        lines.append("  .env search order:")
        for path in doc.envFileSearchOrder {
            lines.append("      \(path)")
        }
        lines.append("")
        lines.append("EXIT CODES")
        for exitCode in doc.exitCodes {
            lines.append("  \(exitCode.code)  \(exitCode.meaning)")
        }
        lines.append("")
        lines.append("EXAMPLES")
        for example in doc.examples {
            lines.append("  \(example.command)")
            lines.append("      \(example.summary)")
        }
        lines.append("")
        lines.append("JSON")
        lines.append("  \(doc.checkJson)")
        lines.append("")
        lines.append("NOTES")
        for note in doc.notes {
            lines.append("  • \(note)")
        }
        return lines.joined(separator: "\n")
    }

    private static func flagLines(_ flag: Flag) -> [String] {
        let names = flag.names.joined(separator: ", ")
        let header = flag.value.map { "\(names) \($0)" } ?? names
        return ["  \(header)", "      \(flag.summary)"]
    }
}
