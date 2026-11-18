import Testing
@testable import Core

@Suite("The base the starting point chip names leads the popover")
struct StartingPointLeadingBaseTests {
    private var offering: WorkspaceSourceOffering {
        WorkspaceSourceOffering(baseBranches: ["bell", "lamp", "main", "rope"])
    }

    private func newBranchRows(
        point: WorkspaceStartingPoint, cameFrom: String? = nil, query: String = ""
    ) -> [WorkspaceSource] {
        let sections = StartingPointMenu.sections(
            offering: offering,
            query: query,
            leadingBases: StartingPointMenu.leadingBases(point: point, cameFrom: cameFrom),
            offersPullRequests: false
        )
        return sections.first { $0.kind == .newBranch }?.rows ?? []
    }

    @Test("an ordinary new draft leads New branch from with the base on its chip")
    func ordinaryDraftLeadsWithItsBase() {
        let rows = newBranchRows(point: .newBranch(from: "main"))
        #expect(rows.map(\.name) == ["main", "bell", "lamp", "rope"])
    }

    @Test("the first row, which the popover selects, is the base the chip promised")
    func firstRowIsTheChipsBase() {
        let sections = StartingPointMenu.sections(
            offering: offering,
            query: "",
            leadingBases: StartingPointMenu.leadingBases(point: .newBranch(from: "main"), cameFrom: nil),
            offersPullRequests: false
        )
        #expect(StartingPointMenu.rows(in: sections).first == .newBranch(from: "main"))
    }

    @Test("a base chosen in the popover leads it the next time it opens")
    func chosenBaseLeads() {
        #expect(newBranchRows(point: .newBranch(from: "rope")).map(\.name) == ["rope", "bell", "lamp", "main"])
    }

    @Test("coming back from a workspace keeps the chip's base first and its branch second")
    func cameFromFollowsTheChip() {
        let rows = newBranchRows(point: .newBranch(from: "main"), cameFrom: "lamp")
        #expect(rows.map(\.name) == ["main", "lamp", "bell", "rope"])
    }

    @Test("the branch you came from is not offered twice when the chip already names it")
    func cameFromSameAsChip() {
        #expect(StartingPointMenu.leadingBases(point: .newBranch(from: "lamp"), cameFrom: "lamp") == ["lamp"])
    }

    @Test("a chip on an existing branch leaves only the branch you came from to lead")
    func existingBranchChip() {
        let point = WorkspaceStartingPoint.existingBranch(ExistingBranch(name: "bell", isLocal: true))
        #expect(StartingPointMenu.leadingBases(point: point, cameFrom: "lamp") == ["lamp"])
        #expect(StartingPointMenu.leadingBases(point: point, cameFrom: nil).isEmpty)
    }

    @Test("once something is typed, the search decides the order")
    func typingDropsTheLead() {
        #expect(newBranchRows(point: .newBranch(from: "main"), query: "rope").map(\.name) == ["rope"])
        #expect(newBranchRows(point: .newBranch(from: "main"), query: "l").first?.name != "main")
    }
}
