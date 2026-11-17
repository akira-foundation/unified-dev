import Foundation

public enum SearchPanelProfiles {
    public static let detail = "Switch profile"

    public static func hits(
        _ needle: String, in profiles: [Profile], active: ProfileID
    ) -> [SearchPanelProfileHit] {
        guard needle.count >= SearchPanelCommands.inlineMinimumQueryLength else { return [] }
        return profiles
            .enumerated()
            .compactMap { position, profile -> (offset: Int, hit: SearchPanelProfileHit)? in
                guard ProfileNavigation.maySwitch(to: profile.id, from: active, among: profiles),
                      let found = FuzzyMatch.hit(profile.name, query: needle)
                else { return nil }
                let hit = SearchPanelProfileHit(
                    profile: profile,
                    highlights: found.positions,
                    score: found.score,
                    keyText: ProfileShortcut.digits.contains(position + 1)
                        ? ProfileShortcut.key(at: position + 1).display
                        : nil
                )
                return (position, hit)
            }
            .sorted { left, right in
                left.hit.score == right.hit.score
                    ? left.offset < right.offset
                    : left.hit.score > right.hit.score
            }
            .map(\.hit)
    }

    public static func lead(
        _ profiles: [SearchPanelProfileHit], over workspaces: [SearchPanelWorkspaceHit]
    ) -> Bool {
        guard let best = profiles.first?.score else { return false }
        return best >= (workspaces.first?.score ?? 0)
    }
}
