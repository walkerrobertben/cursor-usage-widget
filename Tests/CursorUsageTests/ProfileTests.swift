import XCTest
import CursorUsageHTML
@testable import CursorUsageCore

final class ProfileTests: XCTestCase {
    func testLoadingStateShowsCursorLoadingChipAndMenuCopy() {
        let state = UsageDisplayState()
        let presentation = MenuPresentation.make(from: state, calendar: TestCalendar.snapshot)
        let menubar = MenubarPresentation.make(from: state)

        XCTAssertEqual(MenubarPresentation.loadingChip, "Cursor: Loading...")
        XCTAssertEqual(menubar, .loading)
        XCTAssertEqual(menubar.compactLine, "Cursor: Loading...")
        XCTAssertEqual(presentation.menubar.kind, .loading)
        XCTAssertEqual(presentation.menubar.segments, ["Cursor: Loading..."])
        XCTAssertEqual(presentation.menubar.text, "Cursor: Loading...")
        XCTAssertEqual(presentation.text(matching: "loading"), MenuPresentation.loadingMessage)
        XCTAssertTrue(presentation.menubar.visible)
    }

    func testHTMLLoadingChipIsVisibleInsteadOfHidden() {
        let html = MenuHTMLRenderer.document(
            MenuPresentation.make(from: UsageDisplayState(), calendar: TestCalendar.snapshot),
            appearance: .light,
            title: "loading"
        )
        XCTAssertTrue(html.contains("Cursor: Loading..."))
        XCTAssertTrue(html.contains("menubar visible loading"))
        XCTAssertFalse(html.contains("(hidden)"))
        XCTAssertTrue(html.contains(MenuPresentation.loadingMessage))
    }

    func testDefaultApplicationSupportFolderIsLabeledDefault() {
        let path = "/Users/ada/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        XCTAssertEqual(CursorProfileLabel.uniqueTitles(forDatabasePaths: [path]), ["Default"])
    }

    func testUserDataDirFolderNameBecomesTitle() {
        let nightly = "/Users/ada/Library/Application Support/Cursor Nightly/User/globalStorage/state.vscdb"
        let work = "/Users/ada/.cursor-profiles/work/User/globalStorage/state.vscdb"
        XCTAssertEqual(
            CursorProfileLabel.uniqueTitles(forDatabasePaths: [nightly, work]),
            ["Cursor Nightly", "work"]
        )
    }

    func testSameAccountKeepsNamedProfileOverDefault() {
        let defaultProfile = CursorProfile(
            databasePath: "/Users/ada/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            title: "Default",
            source: "default Application Support",
            userId: "acct_work"
        )
        let named = CursorProfile(
            databasePath: "/Users/ada/dev/Cursor/Data/Work/User/globalStorage/state.vscdb",
            title: "Work",
            source: "running Cursor --user-data-dir",
            userId: "acct_work"
        )
        let personal = CursorProfile(
            databasePath: "/Users/ada/dev/Cursor/Data/Personal/User/globalStorage/state.vscdb",
            title: "Personal",
            source: "running Cursor --user-data-dir",
            userId: "acct_personal"
        )

        let collapsed = CursorProfile.uniqueAccounts([defaultProfile, personal, named])
        XCTAssertEqual(collapsed.map(\.title), ["Work", "Personal"])
        XCTAssertEqual(collapsed.map(\.userId), ["acct_work", "acct_personal"])
    }

    func testDefaultStaysWhenItsAccountIsUnique() {
        let defaultProfile = CursorProfile(
            databasePath: "/Users/ada/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            title: "Default",
            source: "default Application Support",
            userId: "acct_home"
        )
        let personal = CursorProfile(
            databasePath: "/Users/ada/dev/Cursor/Data/Personal/User/globalStorage/state.vscdb",
            title: "Personal",
            source: "running Cursor --user-data-dir",
            userId: "acct_personal"
        )

        XCTAssertEqual(
            CursorProfile.uniqueAccounts([defaultProfile, personal]).map(\.title),
            ["Default", "Personal"]
        )
    }

    func testDuplicateFolderNamesUseParentPath() {
        let left = "/tmp/left/work/User/globalStorage/state.vscdb"
        let right = "/tmp/right/work/User/globalStorage/state.vscdb"
        XCTAssertEqual(
            CursorProfileLabel.uniqueTitles(forDatabasePaths: [left, right]),
            ["left/work", "right/work"]
        )
    }

    func testSiblingDiscoveryFindsCursorFoldersAndSkipsOthers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-profile-discovery-\(UUID().uuidString)")
        let appSupport = root.appendingPathComponent("Application Support")
        defer { try? FileManager.default.removeItem(at: root) }

        try touchDatabase(inUserDataDir: appSupport.appendingPathComponent("Cursor").path)
        try touchDatabase(inUserDataDir: appSupport.appendingPathComponent("Cursor Nightly").path)
        try touchDatabase(inUserDataDir: appSupport.appendingPathComponent("Cursor-Work").path)
        try FileManager.default.createDirectory(
            at: appSupport.appendingPathComponent("CursorUsage"),
            withIntermediateDirectories: true
        )
        try touchDatabase(inUserDataDir: appSupport.appendingPathComponent("Code").path)

        let found = CursorProfileDiscovery.userDataDirs(inApplicationSupport: appSupport.path)
        XCTAssertEqual(
            Set(found.map { URL(fileURLWithPath: $0).lastPathComponent }),
            ["Cursor", "Cursor Nightly", "Cursor-Work"]
        )
    }

    func testMenuOmitsSwitcherWhenOnlyOneProfileExists() async throws {
        let presentation = try await ScenarioLoad.presentation(
            .ultra,
            profiles: [
                CursorProfileOption(id: "/tmp/only", title: "Default", userId: "only", isSelected: true),
            ]
        )
        XCTAssertNil(presentation.profileSwitcher)
        XCTAssertFalse(presentation.roleOrder.contains(MenuPresentation.profileSwitcherRole))
    }

    func testMenuOmitsSwitcherWhenNoProfilesExist() async throws {
        let presentation = try await ScenarioLoad.presentation(.ultra, profiles: [])
        XCTAssertNil(presentation.profileSwitcher)
    }

    func testMenuShowsCurrentProfileSubmenuAfterTheTotal() async throws {
        let presentation = try await ScenarioLoad.presentation(.ultra, profiles: SampleProfiles.three())

        let switcher = try XCTUnwrap(presentation.profileSwitcher)
        XCTAssertEqual(switcher.title, "Current profile: Work")
        XCTAssertEqual(switcher.options.map(\.title), ["Default", "Personal", "Work"])
        XCTAssertEqual(switcher.options.map(\.isSelected), [false, false, true])
        let roles = presentation.roleOrder
        let total = try XCTUnwrap(roles.firstIndex(of: "total"))
        let switcherIndex = try XCTUnwrap(roles.firstIndex(of: MenuPresentation.profileSwitcherRole))
        let cursor = try XCTUnwrap(roles.firstIndex(of: "meter-cursor"))
        XCTAssertLessThan(total, switcherIndex)
        XCTAssertLessThan(switcherIndex, cursor)
        XCTAssertEqual(roles.filter { $0 == MenuPresentation.profileSwitcherRole }.count, 1)
    }

    func testProfileSwitcherFallsBackToFirstOptionWhenNoneSelected() async throws {
        let presentation = try await ScenarioLoad.presentation(
            .ultra,
            profiles: SampleProfiles.three(selected: "")
        )
        XCTAssertEqual(presentation.profileSwitcher?.title, "Current profile: Default")
        XCTAssertEqual(presentation.profileSwitcher?.options.map(\.isSelected), [false, false, false])
    }

    func testOpenMenuRebuildsWhenLoadingBecomesReady() async throws {
        let loading = MenuPresentation.make(
            from: UsageDisplayState(profiles: SampleProfiles.workAndPersonal()),
            calendar: TestCalendar.snapshot
        )
        let ready = try await ScenarioLoad.presentation(.ultra, profiles: SampleProfiles.workAndPersonal())

        XCTAssertEqual(loading.text(matching: "loading"), MenuPresentation.loadingMessage)
        XCTAssertNil(ready.text(matching: "loading"))
        XCTAssertTrue(ready.shouldReplaceOpenMenu(from: loading, isOpen: true))
        XCTAssertFalse(ready.shouldReplaceOpenMenu(from: loading, isOpen: false))
    }

    func testOpenMenuDoesNotRebuildWhenRowsAreUnchanged() {
        let loading = MenuPresentation.make(
            from: UsageDisplayState(profiles: SampleProfiles.workAndPersonal()),
            calendar: TestCalendar.snapshot
        )
        XCTAssertFalse(loading.shouldReplaceOpenMenu(from: loading, isOpen: true))
    }

    func testOpenMenuRebuildsWhenProfilesAppearOnLoadingState() {
        let before = MenuPresentation.make(from: UsageDisplayState(), calendar: TestCalendar.snapshot)
        let after = MenuPresentation.make(
            from: UsageDisplayState(profiles: SampleProfiles.workAndPersonal()),
            calendar: TestCalendar.snapshot
        )
        XCTAssertNil(before.profileSwitcher)
        XCTAssertNotNil(after.profileSwitcher)
        XCTAssertTrue(after.shouldReplaceOpenMenu(from: before, isOpen: true))
    }

    func testOpenMenuIgnoresMenubarOnlyChanges() async throws {
        var (state, _) = try await ScenarioLoad.state(.ultra)
        state.profiles = SampleProfiles.workAndPersonal()
        let before = MenuPresentation.make(from: state, calendar: TestCalendar.snapshot)
        state.autoPercentIncreased = true
        let after = MenuPresentation.make(from: state, calendar: TestCalendar.snapshot)

        XCTAssertNotEqual(before.menubar, after.menubar)
        XCTAssertEqual(before.rows, after.rows)
        XCTAssertFalse(after.shouldReplaceOpenMenu(from: before, isOpen: true))
    }

    func testOpenMenuRebuildsWhenReadyUsageChanges() async throws {
        let empty = try await ScenarioLoad.presentation(.emptyMeters).0
        let full = try await ScenarioLoad.presentation(.fullMeters).0
        XCTAssertTrue(full.shouldReplaceOpenMenu(from: empty, isOpen: true))
    }

    func testLoadingMenuStillOffersProfileSubmenu() {
        let presentation = MenuPresentation.make(
            from: UsageDisplayState(profiles: SampleProfiles.workAndPersonal()),
            calendar: TestCalendar.snapshot
        )
        XCTAssertEqual(presentation.menubar.kind, .loading)
        XCTAssertEqual(presentation.menubar.text, "Cursor: Loading...")
        XCTAssertEqual(presentation.profileSwitcher?.title, "Current profile: Work")
        XCTAssertEqual(presentation.profileSwitcher?.options.map(\.title), ["Work", "Personal"])
        XCTAssertEqual(presentation.text(matching: "loading"), MenuPresentation.loadingMessage)
    }

    func testUnauthenticatedMenuStillOffersProfileSubmenu() {
        let presentation = MenuPresentation.make(
            from: UsageDisplayState(
                isAuthenticated: false,
                authErrorMessage: MenuPresentation.authFallbackMessage,
                profiles: SampleProfiles.workAndPersonal()
            ),
            calendar: TestCalendar.snapshot
        )
        XCTAssertEqual(presentation.menubar.kind, .warning(text: "⚠ Cursor"))
        XCTAssertEqual(presentation.profileSwitcher?.title, "Current profile: Work")
        XCTAssertEqual(presentation.profileSwitcher?.options.map(\.title), ["Work", "Personal"])
    }

    func testHTMLRendersProfileSwitcherWithSelectedCheck() async throws {
        let html = MenuHTMLRenderer.document(
            try await ScenarioLoad.presentation(.ultra, profiles: SampleProfiles.three()),
            appearance: .light,
            title: "profiles"
        )
        XCTAssertTrue(html.contains("Current profile: Work"))
        XCTAssertTrue(html.contains("data-role=\"profileSwitcher\""))
        XCTAssertTrue(html.contains("profile-switcher open"))
        XCTAssertTrue(html.contains("submenu-arrow"))
        XCTAssertTrue(html.contains("profile-submenu"))
        XCTAssertTrue(html.contains("left: calc(100% - 2px)"))
        XCTAssertTrue(html.contains("profile-option selected"))
        XCTAssertTrue(html.contains("✓"))
        XCTAssertTrue(html.contains("Default"))
        XCTAssertTrue(html.contains("Personal"))
        XCTAssertTrue(html.contains("Work"))
        XCTAssertFalse(html.contains("padding: 4px 0 0 12px"))
    }

    func testHTMLEscapesProfileTitles() {
        let html = MenuHTMLRenderer.document(
            MenuPresentation.make(
                from: UsageDisplayState(
                    isAuthenticated: false,
                    authErrorMessage: MenuPresentation.authFallbackMessage,
                    profiles: [
                        CursorProfileOption(
                            id: "/tmp/a",
                            title: "A & B <Work>",
                            userId: "a",
                            isSelected: true
                        ),
                        CursorProfileOption(id: "/tmp/b", title: "Personal", userId: "b", isSelected: false),
                    ]
                ),
                calendar: TestCalendar.snapshot
            )
        )
        XCTAssertTrue(html.contains("Current profile: A &amp; B &lt;Work&gt;"))
        XCTAssertTrue(html.contains("A &amp; B &lt;Work&gt;"))
        XCTAssertFalse(html.contains("A & B <Work>"))
    }

    func testResolvePrefersSelectedDatabase() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3"), "sqlite3 is required")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-profile-auth-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try writeAuthDatabase(in: root.appendingPathComponent("first").path, userId: "test_profile_first")
        let second = try writeAuthDatabase(in: root.appendingPathComponent("second").path, userId: "test_profile_second")
        let overrides = CursorAuthOverrides(stateDB: first, additionalStateDBs: [second])

        let preferred = try CursorAuth.resolve(overrides: overrides, preferring: second)
        XCTAssertEqual(preferred.userId, "test_profile_second")
        XCTAssertEqual(preferred.source, "selected profile")

        let fallback = try CursorAuth.resolve(overrides: overrides)
        XCTAssertEqual(fallback.userId, "test_profile_first")
    }

    func testListUsableProfilesIncludesOverrideDatabases() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3"), "sqlite3 is required")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-profile-list-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let work = try writeAuthDatabase(in: root.appendingPathComponent("work").path, userId: "test_profile_work")
        let personal = try writeAuthDatabase(
            in: root.appendingPathComponent("personal").path,
            userId: "test_profile_personal"
        )

        let profiles = CursorAuth.listUsableProfiles(
            overrides: CursorAuthOverrides(additionalStateDBs: [work, personal])
        )
        let testProfiles = profiles.filter { $0.userId.hasPrefix("test_profile_") }
        XCTAssertEqual(Set(testProfiles.map(\.userId)), ["test_profile_work", "test_profile_personal"])
        XCTAssertEqual(Set(testProfiles.map(\.title)), ["work", "personal"])
    }

    func testListUsableProfilesDropsDefaultWhenNamedDirHasSameAccount() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3"), "sqlite3 is required")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-profile-dedupe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let defaultDir = root.appendingPathComponent("Library/Application Support/Cursor").path
        let namedDir = root.appendingPathComponent("Work").path
        let defaultDB = try writeAuthDatabase(in: defaultDir, userId: "test_profile_shared")
        let namedDB = try writeAuthDatabase(in: namedDir, userId: "test_profile_shared")

        let profiles = CursorAuth.listUsableProfiles(
            overrides: CursorAuthOverrides(additionalStateDBs: [defaultDB, namedDB])
        )
        let testProfiles = profiles.filter { $0.userId == "test_profile_shared" }
        XCTAssertEqual(testProfiles.map(\.databasePath), [namedDB])
        XCTAssertFalse(testProfiles.contains { CursorProfile.isDefaultAccountHome($0) })
    }

    func testListUsableProfilesSortsDefaultFirstThenTitle() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3"), "sqlite3 is required")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-profile-sort-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let defaultDB = try writeAuthDatabase(
            in: root.appendingPathComponent("Library/Application Support/Cursor").path,
            userId: "test_profile_sort_z"
        )
        let workDB = try writeAuthDatabase(in: root.appendingPathComponent("Work").path, userId: "test_profile_sort_w")
        let personalDB = try writeAuthDatabase(
            in: root.appendingPathComponent("Personal").path,
            userId: "test_profile_sort_p"
        )

        let profiles = CursorAuth.listUsableProfiles(
            overrides: CursorAuthOverrides(additionalStateDBs: [workDB, personalDB, defaultDB])
        )
        let testProfiles = profiles.filter { $0.userId.hasPrefix("test_profile_sort_") }
        XCTAssertEqual(testProfiles.map(\.title), ["Default", "Personal", "Work"])
    }

    func testListUsableProfilesSkipsDatabasesWithoutTokens() throws {
        try XCTSkipIf(!FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3"), "sqlite3 is required")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-profile-skip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let valid = try writeAuthDatabase(in: root.appendingPathComponent("valid").path, userId: "test_profile_valid")
        let empty = root.appendingPathComponent("empty/User/globalStorage/state.vscdb")
        try FileManager.default.createDirectory(at: empty.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: empty)

        let profiles = CursorAuth.listUsableProfiles(
            overrides: CursorAuthOverrides(additionalStateDBs: [empty.path, valid])
        )
        XCTAssertEqual(profiles.filter { $0.userId.hasPrefix("test_profile_") }.map(\.userId), ["test_profile_valid"])
    }

    func testResolveRequiredSelectedProfileMissingThrows() {
        XCTAssertThrowsError(
            try CursorAuth.resolve(
                overrides: CursorAuthOverrides(),
                preferring: "/tmp/does-not-exist-\(UUID().uuidString)/state.vscdb",
                required: true
            )
        ) { error in
            guard case let CursorAuthError.noDatabaseFound(searched) = error else {
                return XCTFail("expected noDatabaseFound, got \(error)")
            }
            XCTAssertTrue(searched.contains { $0.contains("selected profile") })
        }
    }

    private func touchDatabase(inUserDataDir directory: String) throws {
        let db = URL(fileURLWithPath: directory)
            .appendingPathComponent(CursorStateDatabase.relativePath)
        try FileManager.default.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: db)
    }

    private func writeAuthDatabase(in userDataDir: String, userId: String) throws -> String {
        let db = URL(fileURLWithPath: userDataDir)
            .appendingPathComponent(CursorStateDatabase.relativePath)
        try FileManager.default.createDirectory(at: db.deletingLastPathComponent(), withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            db.path,
            """
            CREATE TABLE ItemTable (key TEXT, value TEXT);
            INSERT INTO ItemTable (key, value) VALUES ('cursorAuth/accessToken', '\(jwt(userId: userId))');
            """,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return db.path
    }

    private func jwt(userId: String) -> String {
        func encode(_ object: [String: String]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encode(["alg": "none"])).\(encode(["sub": "auth0|\(userId)"])).sig"
    }
}
