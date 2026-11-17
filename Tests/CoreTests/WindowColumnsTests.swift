import CoreGraphics
import Foundation
import Testing
@testable import Core

@Suite("Window columns")
struct WindowColumnsTests {
    private static let widths = WindowWidths(
        sidebar: 420, sidebarMinimum: 200, detail: 560, inspector: 320, divider: 1
    )

    private static let wide: CGFloat = 1_800

    private static let narrow: CGFloat = 700

    private func columns(
        _ selection: SidebarSelection,
        hasInspectorSubject: Bool = false,
        reservesInspectorRoom: Bool = false,
        hidesSidebar: Bool = false,
        hidesInspector: Bool = false,
        availableWidth: CGFloat = WindowColumnsTests.wide
    ) -> WindowColumns {
        WindowColumns.resolve(
            selection: selection,
            hasInspectorSubject: hasInspectorSubject,
            reservesInspectorRoom: reservesInspectorRoom,
            hidesSidebar: hidesSidebar,
            hidesInspector: hidesInspector,
            widths: Self.widths,
            availableWidth: availableWidth
        )
    }

    private static let everySelection: [SidebarSelection] = [
        .home,
        .ask,
        .workspace(WorkspaceID("live")),
        .archived(WorkspaceID("gone")),
        .subagent(WorkspaceID("live"), SubagentID("sub")),
        .subagentCall(WorkspaceID("live"), toolUseID: "toolu_1"),
        .crew(WorkspaceID("live"), SessionID("session")),
        .draft(RepoID("repo")),
    ]

    @Test("an archived selection keeps the sidebar and the centre column")
    func archivedKeepsItsColumns() {
        let resolved = columns(.archived(WorkspaceID("gone")))
        #expect(resolved.drawsSidebar)
        #expect(resolved.reach == .all)
        #expect(!resolved.drawsInspector)
    }

    @Test("an archived selection in a window too narrow for the sidebar still draws the centre column")
    func archivedInANarrowWindow() {
        let resolved = columns(.archived(WorkspaceID("gone")), availableWidth: Self.narrow)
        #expect(!resolved.drawsSidebar)
        #expect(resolved.reach == .withoutSidebar)
        #expect(!resolved.drawsInspector)
    }

    @Test("every reach the window can take shows the centre column")
    func theCentreColumnIsNeverTheOneThatGoes() {
        let everyReachShowsTheCentre = WindowColumns.Reach.allCases.allSatisfy { $0.showsCentre }
        #expect(everyReachShowsTheCentre)
        for selection in Self.everySelection {
            for hasSubject in [true, false] {
                for reserves in [true, false] {
                    for hides in [true, false] {
                        for width in [Self.wide, Self.narrow, 0 as CGFloat] {
                            let resolved = columns(
                                selection,
                                hasInspectorSubject: hasSubject,
                                reservesInspectorRoom: reserves,
                                hidesSidebar: hides,
                                availableWidth: width
                            )
                            #expect(resolved.reach.showsCentre)
                            #expect(resolved.drawsSidebar == (resolved.fitsSidebar && !hides))
                        }
                    }
                }
            }
        }
    }

    @Test("the inspector's room is reserved only when the window reserves it")
    func theInspectorRoomIsTheWindowsToReserve() {
        let reserved = columns(
            .workspace(WorkspaceID("live")), hasInspectorSubject: true,
            reservesInspectorRoom: true, availableWidth: 800
        )
        let unreserved = columns(
            .workspace(WorkspaceID("live")), hasInspectorSubject: true,
            reservesInspectorRoom: false, availableWidth: 800
        )

        #expect(!reserved.fitsSidebar)
        #expect(!reserved.drawsSidebar)
        #expect(unreserved.fitsSidebar)
        #expect(unreserved.drawsSidebar)
        #expect(reserved.drawsInspector)
        #expect(unreserved.drawsInspector)
    }

    @Test("a sidebar with no room to be drawn is not one the owner hid")
    func noRoomIsNotTheOwnersDoing() {
        let tight = columns(.home, availableWidth: Self.narrow)
        let hidden = columns(.home, hidesSidebar: true)

        #expect(!tight.fitsSidebar)
        #expect(!tight.drawsSidebar)
        #expect(hidden.fitsSidebar)
        #expect(!hidden.drawsSidebar)
    }

    @Test("the inspector belongs to a live workspace and to nothing else")
    func theInspectorFollowsTheWorkspace() {
        #expect(columns(.workspace(WorkspaceID("live")), hasInspectorSubject: true).drawsInspector)
        #expect(columns(.crew(WorkspaceID("live"), SessionID("s")), hasInspectorSubject: true).drawsInspector)
        #expect(!columns(.workspace(WorkspaceID("live")), hasInspectorSubject: false).drawsInspector)
        #expect(!columns(.archived(WorkspaceID("gone")), hasInspectorSubject: true).drawsInspector)
        #expect(!columns(.home, hasInspectorSubject: true).drawsInspector)
        #expect(!columns(.ask, hasInspectorSubject: true).drawsInspector)
        #expect(!columns(.draft(RepoID("repo")), hasInspectorSubject: true).drawsInspector)
    }

    @Test("hiding the sidebar is the owner's decision and does not fold the centre column away")
    func hidingTheSidebar() {
        let hidden = columns(.workspace(WorkspaceID("live")), hasInspectorSubject: true, hidesSidebar: true)
        #expect(!hidden.drawsSidebar)
        #expect(hidden.reach == .withoutSidebar)
        #expect(hidden.drawsInspector)
    }

    @Test("the profile switcher collapses to its mark only while the sidebar is not drawn")
    func profileMark() {
        #expect(!columns(.home).collapsesProfileSwitcher)
        #expect(columns(.home, hidesSidebar: true).collapsesProfileSwitcher)
        #expect(columns(.home, availableWidth: Self.narrow).collapsesProfileSwitcher)
    }

    @Test("the sidebar ceiling is the room the window has for it")
    func theSidebarCeiling() {
        #expect(columns(.home).sidebarCeiling == Self.widths.sidebar)
        let shared = columns(
            .workspace(WorkspaceID("live")), hasInspectorSubject: true, reservesInspectorRoom: true,
            availableWidth: 1_200
        )
        #expect(shared.sidebarCeiling == 318)
        #expect(columns(.home, availableWidth: Self.narrow).sidebarCeiling == Self.widths.sidebarMinimum)
    }

    @Test("an archived selection is given the room a workspace would have asked the inspector for")
    func archivedDoesNotReserveInspectorRoom() {
        let archived = columns(
            .archived(WorkspaceID("gone")), hasInspectorSubject: true, reservesInspectorRoom: false,
            availableWidth: 1_000
        )
        let live = columns(
            .workspace(WorkspaceID("live")), hasInspectorSubject: true, reservesInspectorRoom: true,
            availableWidth: 1_000
        )
        #expect(archived.drawsSidebar)
        #expect(archived.sidebarCeiling == Self.widths.sidebar)
        #expect(!live.drawsSidebar)
        #expect(!live.fitsSidebar)
    }

    @Test("a hidden inspector is not drawn, and the workspace still offers it")
    func hidingTheInspector() {
        let hidden = columns(.workspace(WorkspaceID("live")), hasInspectorSubject: true, hidesInspector: true)
        #expect(!hidden.drawsInspector)
        #expect(hidden.offersInspector)
        #expect(hidden.drawsSidebar)
    }

    @Test("hiding the inspector gives its room back to the sidebar")
    func hidingTheInspectorFreesItsRoom() {
        let shown = columns(
            .workspace(WorkspaceID("live")), hasInspectorSubject: true,
            reservesInspectorRoom: true, availableWidth: 1_000
        )
        let hidden = columns(
            .workspace(WorkspaceID("live")), hasInspectorSubject: true,
            reservesInspectorRoom: true, hidesInspector: true, availableWidth: 1_000
        )
        #expect(!shown.fitsSidebar)
        #expect(hidden.fitsSidebar)
        #expect(hidden.sidebarCeiling == Self.widths.sidebar)
    }

    @Test("with nothing to inspect there is no inspector to offer, hidden or not")
    func nothingToOffer() {
        for selection in Self.everySelection where selection.workspaceID == nil {
            for hides in [true, false] {
                let resolved = columns(selection, hasInspectorSubject: true, hidesInspector: hides)
                #expect(!resolved.offersInspector, "\(selection)")
                #expect(resolved.inspectorToggleSection == nil, "\(selection)")
            }
        }
        #expect(columns(.workspace(WorkspaceID("live"))).inspectorToggleSection == nil)
    }

    @Test("the toggle sits over the inspector while it is drawn and over the centre once it is hidden")
    func theToggleFollowsTheTrailingSection() {
        let shown = columns(.workspace(WorkspaceID("live")), hasInspectorSubject: true)
        let hidden = columns(.workspace(WorkspaceID("live")), hasInspectorSubject: true, hidesInspector: true)
        #expect(shown.inspectorToggleSection == .inspector)
        #expect(shown.trailingSection == .inspector)
        #expect(hidden.inspectorToggleSection == .centre)
        #expect(hidden.trailingSection == .centre)
    }

    @Test("the trailing items go over the centre whenever the inspector is not drawn")
    func theTrailingSectionIsTheCentreWithoutAnInspector() {
        for selection in Self.everySelection {
            for hasSubject in [true, false] {
                for hides in [true, false] {
                    let resolved = columns(selection, hasInspectorSubject: hasSubject, hidesInspector: hides)
                    #expect((resolved.trailingSection == .inspector) == resolved.drawsInspector, "\(selection)")
                    if let section = resolved.inspectorToggleSection {
                        #expect(section == resolved.trailingSection, "\(selection)")
                    }
                }
            }
        }
    }
}
