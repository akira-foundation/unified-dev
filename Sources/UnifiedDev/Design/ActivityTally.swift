#if DEBUG
import Foundation

@MainActor
enum ActivityTally {
    static var reloads = 0
    static var inboxReloads = 0
    static var changeReads = 0
    static var changeGenerations = 0
    static var subagentRowWrites = 0
    static var sidebarReflows = 0
    static var sidebarRowWrites = 0

    struct Reading {
        var reloads: Int
        var inboxReloads: Int
        var changeReads: Int
        var changeGenerations: Int
        var subagentRowWrites: Int
        var sidebarReflows: Int
        var sidebarRowWrites: Int

        static func - (lhs: Reading, rhs: Reading) -> Reading {
            Reading(
                reloads: lhs.reloads - rhs.reloads,
                inboxReloads: lhs.inboxReloads - rhs.inboxReloads,
                changeReads: lhs.changeReads - rhs.changeReads,
                changeGenerations: lhs.changeGenerations - rhs.changeGenerations,
                subagentRowWrites: lhs.subagentRowWrites - rhs.subagentRowWrites,
                sidebarReflows: lhs.sidebarReflows - rhs.sidebarReflows,
                sidebarRowWrites: lhs.sidebarRowWrites - rhs.sidebarRowWrites
            )
        }
    }

    static func read() -> Reading {
        Reading(
            reloads: reloads, inboxReloads: inboxReloads,
            changeReads: changeReads, changeGenerations: changeGenerations,
            subagentRowWrites: subagentRowWrites, sidebarReflows: sidebarReflows,
            sidebarRowWrites: sidebarRowWrites
        )
    }
}
#endif
