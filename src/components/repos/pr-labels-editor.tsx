import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Check, Plus, Search, X } from "lucide-react";
import { toast } from "sonner";

import { useI18n } from "@/i18n/i18n";
import { queryKeys } from "@/lib/query-keys";
import { useNavigationStore } from "@/stores/navigation-store";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";

interface RepoLabel {
  name: string;
  color: string;
  description: string | null;
}

interface PrLabelsEditorProps {
  organizationId: string;
  repoName: string;
  prNumber: number;
  labels: string[];
}

function badgeStyles(color: string): React.CSSProperties {
  const hex = color.replace(/^#/, "");
  if (hex.length !== 6) {
    return { backgroundColor: "#888888", color: "#ffffff" };
  }
  const r = parseInt(hex.slice(0, 2), 16);
  const g = parseInt(hex.slice(2, 4), 16);
  const b = parseInt(hex.slice(4, 6), 16);
  const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return {
    backgroundColor: `#${hex}`,
    color: luminance > 0.6 ? "#0a0a0a" : "#ffffff",
  };
}

function sameSet(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const setA = new Set(a);
  for (const item of b) if (!setA.has(item)) return false;
  return true;
}

export function PrLabelsEditor({ organizationId, repoName, prNumber, labels }: PrLabelsEditorProps) {
  const { t } = useI18n();
  const queryClient = useQueryClient();
  const activePr = useNavigationStore((s) => s.activePr);
  const setActivePr = useNavigationStore((s) => s.setActivePr);

  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [draft, setDraft] = useState<string[]>(labels);
  const draftAtOpenRef = useRef<string[]>(labels);

  useEffect(() => {
    if (!open) setDraft(labels);
  }, [labels, open]);

  const labelsQuery = useQuery({
    queryKey: ["pr-repo-labels", organizationId, repoName],
    queryFn: () => invoke<RepoLabel[]>("list_pr_repo_labels", { organizationId, repoName }),
    staleTime: 60 * 1000,
  });

  const writeStore = (next: string[]) => {
    if (activePr && activePr.number === prNumber) {
      setActivePr({ ...activePr, labels: next });
    }
  };

  const setLabelsMutation = useMutation({
    mutationFn: (next: string[]) =>
      invoke<string[]>("set_pr_labels", { organizationId, repoName, prNumber, labels: next }),
    onSuccess: (updated) => {
      queryClient.invalidateQueries({ queryKey: queryKeys.pullRequests(organizationId, repoName) });
      writeStore(updated);
      setDraft(updated);
    },
    onError: (err) => {
      writeStore(draftAtOpenRef.current);
      setDraft(draftAtOpenRef.current);
      toast.error(String(err));
    },
  });

  const createLabelMutation = useMutation({
    mutationFn: (name: string) =>
      invoke<RepoLabel>("create_pr_repo_label", {
        organizationId,
        repoName,
        name,
        color: null,
        description: null,
      }),
    onSuccess: (label) => {
      queryClient.invalidateQueries({ queryKey: ["pr-repo-labels", organizationId, repoName] });
      setSearch("");
      setDraft((cur) => (cur.includes(label.name) ? cur : [...cur, label.name]));
    },
    onError: (err) => {
      toast.error(String(err));
    },
  });

  const toggle = (name: string) => {
    setDraft((cur) => (cur.includes(name) ? cur.filter((l) => l !== name) : [...cur, name]));
  };

  const remove = (name: string) => {
    const next = draft.filter((l) => l !== name);
    setDraft(next);
    writeStore(next);
    setLabelsMutation.mutate(next);
  };

  const handleOpenChange = (next: boolean) => {
    setOpen(next);
    if (next) {
      draftAtOpenRef.current = labels;
      setDraft(labels);
      setSearch("");
      return;
    }
    if (!sameSet(draft, draftAtOpenRef.current)) {
      writeStore(draft);
      setLabelsMutation.mutate(draft);
    }
  };

  const known = labelsQuery.data ?? [];
  const filtered = search
    ? known.filter((l) => l.name.toLowerCase().includes(search.toLowerCase()))
    : known;
  const knownByName = new Map(known.map((l) => [l.name, l]));
  const chipLabels = open ? draft : labels;

  return (
    <div className="flex flex-col gap-1.5 px-1 py-1">
      <div className="flex flex-wrap items-center gap-1.5">
        {chipLabels.map((name) => {
          const meta = knownByName.get(name);
          return (
            <span
              key={name}
              className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium"
              style={badgeStyles(meta?.color ?? "888888")}
            >
              {name}
              <button
                type="button"
                onClick={() => remove(name)}
                className="rounded-full p-0.5 transition-colors hover:bg-black/20"
                aria-label={t("components.prDetail.labels.remove")}
              >
                <X className="h-2.5 w-2.5" />
              </button>
            </span>
          );
        })}
        <Popover open={open} onOpenChange={handleOpenChange}>
          <PopoverTrigger asChild>
            <button
              type="button"
              className="inline-flex items-center gap-1 rounded-full border border-dashed border-zinc-300 px-2 py-0.5 text-[11px] text-zinc-500 hover:border-zinc-400 hover:text-zinc-700 dark:border-zinc-700 dark:hover:border-zinc-500 dark:hover:text-zinc-200"
            >
              <Plus className="h-3 w-3" />
              {t("components.prDetail.labels.add")}
            </button>
          </PopoverTrigger>
          <PopoverContent align="start" className="w-72 p-2">
            <div className="flex items-center gap-2 border-b border-zinc-100 px-2 py-1.5 dark:border-zinc-800">
              <Search className="h-3.5 w-3.5 text-zinc-400" />
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder={t("components.prDetail.labels.search")}
                className="flex-1 bg-transparent text-[13px] outline-none placeholder:text-zinc-400"
              />
            </div>
            <div className="max-h-64 overflow-y-auto py-1">
              {labelsQuery.isLoading && (
                <div className="px-3 py-2 text-[12px] text-zinc-500">{t("components.prDetail.labels.loading")}</div>
              )}
              {labelsQuery.isError && (
                <div className="px-3 py-2 text-[12px] text-red-500">{String(labelsQuery.error)}</div>
              )}
              {!labelsQuery.isLoading && !labelsQuery.isError && filtered.length === 0 && (
                <div className="px-3 py-2 text-[12px] text-zinc-500">{t("components.prDetail.labels.empty")}</div>
              )}
              {filtered.map((l) => {
                const active = draft.includes(l.name);
                return (
                  <button
                    key={l.name}
                    type="button"
                    onClick={() => toggle(l.name)}
                    className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-[13px] hover:bg-zinc-100 dark:hover:bg-white/5"
                  >
                    <span
                      className="inline-block h-2.5 w-2.5 rounded-full"
                      style={{ backgroundColor: `#${l.color.replace(/^#/, "")}` }}
                    />
                    <span className="flex-1 truncate">{l.name}</span>
                    {active && <Check className="h-3.5 w-3.5 text-emerald-500" />}
                  </button>
                );
              })}
              {search.trim() && !known.some((l) => l.name.toLowerCase() === search.trim().toLowerCase()) && (
                <button
                  type="button"
                  onClick={() => createLabelMutation.mutate(search.trim())}
                  className="flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-[13px] text-purple-600 hover:bg-zinc-100 dark:text-purple-300 dark:hover:bg-white/5"
                >
                  <Plus className="h-3.5 w-3.5" />
                  <span className="flex-1 truncate">
                    {t("components.prDetail.labels.create", { name: search.trim() })}
                  </span>
                </button>
              )}
            </div>
          </PopoverContent>
        </Popover>
      </div>
    </div>
  );
}
