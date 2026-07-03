# Frontend

## Pages

`src/pages/` - one file per top-level route, wired through `navigation-store.ts` rather
than a URL-based router (see [Navigation](#navigation) below):

`dashboard.tsx`, `organizations.tsx`, `organization.tsx`, `organization-repos.tsx`,
`providers.tsx`, `provider-detail.tsx`, `import-repositories.tsx`, `repository.tsx`,
`repository-detail.tsx`, `repository-prs.tsx`, `issues.tsx`, `issue-detail.tsx`,
`prs.tsx`, `pr-detail.tsx`, `projects.tsx`, `project-detail.tsx`, `automations.tsx`,
`create-automation.tsx`, `skills.tsx`, `skill-details.tsx`, `skill-source.tsx`,
`mcp.tsx`, `open-source.tsx`, `notifications.tsx`, `settings.tsx`.

## Navigation

`navigation-store.ts` (Zustand, persisted) holds the current page plus the active
provider/org/project/repo/PR/issue selection and a back-navigation history stack. The
app is a single Tauri webview, not a browser - there is no URL bar to reflect route
state, so this store is the source of truth for "where am I," and `useNavigation.ts`
wraps it with initial-page sync on boot.

## State (Zustand stores)

`src/stores/` - grouped by what they own:

- **View state per list page** (persisted): `issue-view-store.ts`, `pr-view-store.ts`
 (view mode - list/kanban, insights panel toggle, hidden columns),
 `org-view-store.ts`/`repo-view-store.ts` (insights panel open/close),
 `filters-store.ts` (namespaced filter maps shared across list views).
- **Kanban overrides**: `useKanbanStore.ts`, `useIssueKanbanStore.ts` - manual
 column placement per card/issue, persisted, layered on top of provider-reported
 status.
- **Agents/chat**: `useAgentsStore.ts` (composed from slices - thread/repo groups,
 messages, file changes, open tabs, persisted), `useAutopilotStore.ts` (job
 orchestration - see [domains/autopilot.md](domains/autopilot.md)).
- **App-level**: `settings-store.ts` (locale, appearance, default AI prompts),
 `sync-settings-store.ts` (per-scope sync toggles/intervals), `usage-store.ts` (daily
 run count/limit), `upgrade-modal-store.ts`, `notifications-store.ts`,
 `onboarding-store.ts`.
- **Feature-specific**: `useOpenSourceFiltersStore.ts`, `useViewedFilesStore.ts`
 (viewed/unviewed file tracking per PR/issue), `search-store.ts` (global search
 palette), `import-view-store.ts`.

## Hooks

`src/hooks/` (~30 files) fall into a few families:

- **Data + mutations**, each wrapping a TanStack Query hook around one or more
 `invoke()` calls: `useOrganizations.ts`, `useProviders.ts`, `useIssueMutations.ts`,
 `useCreateIssueMutation.ts`, `usePrReviewData.ts`, `usePRChecks.ts` (polls PR CI
 status), `useOpenSource.ts`, `useRepositoryDetail.ts`.
- **Editors**: `useIssueBodyEditor.ts`, `usePrBodyEditor.ts`, `useIssueComposerEditor.ts`
  - TipTap markdown editors with a slash-command extension.
- **Chat/agents**: `use-chat-composer.ts` (input state, slash commands, plan mode,
 thinking budget, attachments), `useChatHistory.ts` (localStorage-backed prev/next
 navigation), `useAgentsSidebar.ts`, `useThreadSourceActions.ts` (create a thread from
 an issue/PR/branch picker), `useDelegateIssue.ts`.
- **App-level utilities**: `useAutostart.ts` (OS autostart via Tauri plugin),
 `useUpdater.ts` (Tauri update check/install), `useUsage.ts`, `useAvatar.ts`,
 `useConnectGithub.ts`.
- **UI utilities**: `use-appearance.tsx` (theme), `use-mobile.tsx` (breakpoint media
 query), `use-mutation-with-toast.ts`, `use-image-attachments.ts`,
 `use-browser-handoff-toast.ts` (OAuth-in-browser toast lifecycle), `use-date-label.ts`.

## Command palette

`src/components/layout/command-palette.tsx`, built on `cmdk` (`src/components/ui/command.tsx`
wraps the library). Opens on **Cmd/Ctrl+K** via its own `keydown` listener - not the
`useHotkey` hook. It's a paged menu (`CommandPage = "root" | "agents" | "skills" |
"automations"`; Backspace on an empty search steps back a page) rendering three grouped
command sets from `src/components/commanders/`: `AgentCommander`, `NavigationCommander`,
`SystemCommander`.

## Hotkeys

`src/hooks/useHotkey.ts` is a separate, lightweight single-key binding hook (Cmd/Ctrl+
`<key>`), used ad hoc per page rather than centrally registered:

- `,` → open Settings (`App.tsx`).
- `f` → toggle the insights panel (`issues.tsx`, `prs.tsx`, `organization.tsx`,
 `repository.tsx`).
- `n` → create new (`projects.tsx`, `prs.tsx`, `issues.tsx`, `organizations.tsx`).

## i18n

`src/i18n/locales/{en,pt}/` - one namespace file per topic (`nav.ts`, `common.ts`,
`settings/general.ts`, `settings/misc.ts`, `pages.ts`, `agents.ts`, `issues.ts`,
`autopilot.ts`, `openSource.ts`, `dialogs.ts`, `upgrade.ts`, and others - 42 files per
locale), spread together in each locale's `index.ts`. Reorganized from an earlier
arbitrary `part1.ts`–`part5.ts` split specifically so a translator or contributor can
find the strings for a feature by filename instead of by guessing which numbered chunk
they landed in.
