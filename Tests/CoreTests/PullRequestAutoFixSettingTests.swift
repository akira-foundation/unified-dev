import Testing
import Foundation
@testable import Core

@Suite("Pull request auto fix setting", .tags(.persistence), .scratchDirectory)
struct PullRequestAutoFixSettingTests {
    @Test("off until it is turned on")
    func offByDefault() async throws {
        let store = try makeTestStore("autofix-default")
        let isOn = await PullRequestAutoFixSetting.isOn(repoID: RepoID("r"), in: store)
        #expect(!isOn)
    }

    @Test("stored for one project and not inherited by another")
    func perProject() async throws {
        let store = try makeTestStore("autofix-project")
        try await PullRequestAutoFixSetting.save(true, repoID: RepoID("r"), to: store)
        let mine = await PullRequestAutoFixSetting.isOn(repoID: RepoID("r"), in: store)
        let other = await PullRequestAutoFixSetting.isOn(repoID: RepoID("s"), in: store)
        #expect(mine)
        #expect(!other)
    }

    @Test("turning it off removes the row")
    func turnedOff() async throws {
        let store = try makeTestStore("autofix-off")
        try await PullRequestAutoFixSetting.save(true, repoID: RepoID("r"), to: store)
        try await PullRequestAutoFixSetting.save(false, repoID: RepoID("r"), to: store)
        let stored = try await store.setting(PullRequestAutoFixSetting.key(repoID: RepoID("r")))
        #expect(stored == nil)
    }

    @Test("anything but the stored word reads as off", arguments: [String?.none, "", "true", "ON"])
    func parse(stored: String?) {
        #expect(!PullRequestAutoFixSetting.parse(stored))
    }
}
