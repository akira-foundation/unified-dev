import { create } from "zustand";
import { createJSONStorage, persist } from "zustand/middleware";

import type { AppPage } from "../types/navigation";
import type { PullRequestDto } from "../types/organization";
import type { IssueDto } from "../types/issue";
import type { PullRequestScope } from "@/types/work-visibility";

export interface ActiveRepo {
  name: string;
  owner: string;
  organizationId: string;
}

interface NavigationState {
  currentPage: AppPage;
  activeProviderId: string | null;
  activeOrganizationId: string | null;
  activeProjectId: string | null;
  activeRepo: ActiveRepo | null;
  recentRepos: ActiveRepo[];
  activePr: PullRequestDto | null;
  activeIssue: IssueDto | null;
  issueList: IssueDto[];
  targetPrNumber: number | null;
  targetPrScope: PullRequestScope | null;
  targetCheckName: string | null;
  targetRepoTab: "prs" | "issues" | "branches" | null;
  history: AppPage[];
  canGoBack: boolean;
  isAgentMode: boolean;
  dashboardTab: string;
  setCurrentPage: (page: AppPage) => void;
  navigateTo: (page: AppPage) => void;
  setIsAgentMode: (enabled: boolean) => void;
  goBack: () => void;
  setActiveProviderId: (providerId: string | null) => void;
  setActiveOrganizationId: (organizationId: string | null) => void;
  setActiveProjectId: (projectId: string | null) => void;
  setActiveRepo: (repo: ActiveRepo | null) => void;
  setActivePr: (pr: PullRequestDto | null) => void;
  markActivePrReady: () => void;
  setActiveIssue: (issue: IssueDto | null) => void;
  setIssueList: (list: IssueDto[]) => void;
  setTargetPrNumber: (n: number | null) => void;
  setTargetPrScope: (scope: PullRequestScope | null) => void;
  setTargetCheckName: (name: string | null) => void;
  setTargetRepoTab: (tab: "prs" | "issues" | "branches" | null) => void;
  setDashboardTab: (tab: string) => void;
  settingsTab: string;
  setSettingsTab: (tab: string) => void;
  prDetailTab: string;
  setPrDetailTab: (tab: string) => void;
  repoDetailTab: "prs" | "issues" | "branches";
  setRepoDetailTab: (tab: "prs" | "issues" | "branches") => void;
}

export const useNavigationStore = create<NavigationState>()(
  persist(
    (set, get) => ({
      currentPage: "dashboard",
      activeProviderId: null,
      activeOrganizationId: null,
      activeProjectId: null,
      activeRepo: null,
      recentRepos: [],
      activePr: null,
      activeIssue: null,
      issueList: [],
      targetPrNumber: null,
      targetPrScope: null,
      targetCheckName: null,
      targetRepoTab: null,
      history: [],
      canGoBack: false,
      isAgentMode: false,
      dashboardTab: "overview",
      settingsTab: "general",
      prDetailTab: "overview",
      repoDetailTab: "prs",
      setCurrentPage: (page) => set({ currentPage: page }),
      navigateTo: (page) => {
        const { currentPage, history } = get();
        if (currentPage === page) {
          if (page === "agents") {
            set({ isAgentMode: true });
          }
          return;
        }

        const nextHistory = [...history, currentPage].slice(-20);
        const updates: Partial<NavigationState> = {
          currentPage: page,
          history: nextHistory,
          canGoBack: nextHistory.length > 0,
        };

        if (page === "agents") {
          updates.isAgentMode = true;
        } else {
          updates.isAgentMode = false;
        }

        set(updates);
      },
      setIsAgentMode: (enabled) => set({ isAgentMode: enabled }),
      goBack: () => {
        const { history } = get();
        if (history.length === 0) {
          return;
        }
        const nextHistory = history.slice(0, -1);
        const previous = history[history.length - 1];
        set({
          currentPage: previous,
          history: nextHistory,
          canGoBack: nextHistory.length > 0,
          isAgentMode: previous === "agents",
        });
      },
      setActiveProviderId: (providerId) => set({ activeProviderId: providerId }),
      setActiveOrganizationId: (organizationId) => set({ activeOrganizationId: organizationId }),
      setActiveProjectId: (projectId) => set({ activeProjectId: projectId }),
      setActiveRepo: (repo) => {
        if (!repo) {
          set({ activeRepo: null });
          return;
        }
        const { recentRepos } = get();
        const key = `${repo.organizationId}:${repo.name}`;
        const next = [
          repo,
          ...recentRepos.filter(
            (r) => `${r.organizationId}:${r.name}` !== key,
          ),
        ].slice(0, 5);
        set({ activeRepo: repo, recentRepos: next });
      },
      setActivePr: (pr) => set({ activePr: pr }),
      markActivePrReady: () =>
        set((state) => (state.activePr ? { activePr: { ...state.activePr, is_draft: false } } : {})),
      setActiveIssue: (issue) => set({ activeIssue: issue }),
      setIssueList: (list) => set({ issueList: list }),
      setTargetPrNumber: (n) => set({ targetPrNumber: n }),
      setTargetPrScope: (scope) => set({ targetPrScope: scope }),
      setTargetCheckName: (name) => set({ targetCheckName: name }),
      setTargetRepoTab: (tab) => set({ targetRepoTab: tab }),
      setDashboardTab: (tab) => set({ dashboardTab: tab }),
      setSettingsTab: (tab) => set({ settingsTab: tab }),
      setPrDetailTab: (tab) => set({ prDetailTab: tab }),
      setRepoDetailTab: (tab) => set({ repoDetailTab: tab }),
    }),
    {
      name: "unified_dev_navigation",
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({
        currentPage: state.currentPage,
        activeProviderId: state.activeProviderId,
        activeOrganizationId: state.activeOrganizationId,
        activeProjectId: state.activeProjectId,
        activeRepo: state.activeRepo,
        activePr: state.activePr,
        activeIssue: state.activeIssue,
        targetRepoTab: state.targetRepoTab,
        recentRepos: state.recentRepos,
        history: state.history,
        isAgentMode: state.isAgentMode,
        dashboardTab: state.dashboardTab,
        settingsTab: state.settingsTab,
        prDetailTab: state.prDetailTab,
        repoDetailTab: state.repoDetailTab,
      }),
      onRehydrateStorage: () => (state) => {
        if (state) {
          state.canGoBack = state.history.length > 0;
          state.isAgentMode = state.isAgentMode || state.currentPage === "agents";
        }
      },
    },
  ),
);
