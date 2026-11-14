import Foundation
@testable import Core

enum TestScenarios {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path

    static let codexModel = "gpt-5.6-sol"

    static func shipped(_ name: String) throws -> PreviewScenario {
        try PreviewScenario.read(path: repositoryRoot + "/Tools/scenarios/\(name).json")
    }
}
