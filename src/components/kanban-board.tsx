import {
  DndContext,
  DragEndEvent,
  DragOverlay,
  DragStartEvent,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import { SortableContext, sortableKeyboardCoordinates, useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { Calendar, Circle, CircleDot, CheckCircle2, XCircle } from "lucide-react";
import { createPortal } from "react-dom";
import { useMemo, useState } from "react";
import { useDroppable } from "@dnd-kit/core";
import { invoke } from "@tauri-apps/api/core";
import { useQueries, useQuery } from "@tanstack/react-query";
import { useI18n } from "@/i18n/i18n";

import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { repositorySelectionService } from "@/services/repositorySelectionService";
import { useNavigationStore } from "@/stores/navigation-store";
import { useKanbanStore } from "@/stores/useKanbanStore";
import { queryKeys } from "@/lib/query-keys";
import { cache } from "@/config/cache";
import type { OrganizationRepoWithOrg, PullRequestDto } from "@/types/organization";

type ColumnId = "todo" | "review" | "inprogress" | "done";

interface KanbanCardType {
  id: string;
  title: string;
  repo: string;
  date: string;
  author: string | null;
  columnId: ColumnId;
  pr: PullRequestDto;
  activeRepo: { name: string; owner: string; organizationId: string };
}

const COLUMN_IDS: ColumnId[] = ["todo", "inprogress", "review", "done"];

function ColumnIcon({ id }: { id: ColumnId }) {
  const cls = "h-3.5 w-3.5";
  if (id === "todo")       return <Circle        className={cn(cls, "text-zinc-400")} />;
  if (id === "inprogress") return <CircleDot     className={cn(cls, "text-blue-400")} />;
  if (id === "review")     return <CircleDot     className={cn(cls, "text-amber-400")} />;
  return                          <CheckCircle2  className={cn(cls, "text-emerald-400")} />;
}

function mapPrToColumn(pr: PullRequestDto): ColumnId {
  if (pr.merged_at !== null) return "done";
  if (pr.ci_status === "success" && pr.reviewers.length > 0) return "review";
  if (pr.ci_status === "success") return "inprogress";
  return "todo";
}

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("pt-PT", { day: "2-digit", month: "short" });
}

export function KanbanBoard({ compact = false }: { compact?: boolean }) {
  const { t } = useI18n();
  const { setActiveRepo, setActivePr, navigateTo, setDashboardTab } = useNavigationStore();

  const COLUMNS: { id: ColumnId; title: string; borderColor: string }[] = [
    { id: "todo",        title: t("kanban.columns.open"),  borderColor: "border-t-zinc-500"    },
    { id: "inprogress",  title: t("kanban.columns.build"), borderColor: "border-t-blue-500"    },
    { id: "review",      title: t("kanban.columns.ready"), borderColor: "border-t-amber-500"   },
    { id: "done",        title: t("kanban.columns.merge"), borderColor: "border-t-emerald-500" },
  ];

  const { data: allRepos = [], isLoading: reposLoading } = useQuery({
    queryKey: queryKeys.allRepositories(),
    queryFn: () => repositorySelectionService.listAllSelectedRepositories(),
    staleTime: cache.staleTime.short,
  });

  const prQueries = useQueries({
    queries: allRepos.map((repo: OrganizationRepoWithOrg) => ({
      queryKey: queryKeys.pullRequests(repo.organization_id, repo.repo_name),
      queryFn: () =>
        invoke<PullRequestDto[]>("list_repo_pull_requests", {
          organizationId: repo.organization_id,
          repoName: repo.repo_name,
        }),
      staleTime: cache.staleTime.realtime,
    })),
  });

  const isLoadingPrs = prQueries.some((q) => q.isLoading);

  const allCards = useMemo<KanbanCardType[]>(() => {
    return allRepos.flatMap((repo: OrganizationRepoWithOrg, idx: number) => {
      const prs = prQueries[idx]?.data ?? [];
      return prs
        .filter((pr) => pr.state === "open" || pr.merged_at !== null)
        .map((pr): KanbanCardType => ({
          id: `${repo.organization_id}:${repo.repo_name}:${pr.id}`,
          title: pr.title,
          repo: `${repo.owner}/${repo.repo_name}`,
          date: formatDate(pr.updated_at),
          author: pr.author,
          columnId: mapPrToColumn(pr),
          pr,
          activeRepo: {
            name: repo.repo_name,
            owner: repo.owner,
            organizationId: repo.organization_id,
          },
        }));
    });
  }, [allRepos, prQueries]);

  const { overrides, setOverride } = useKanbanStore();
  const [activeId, setActiveId] = useState<string | null>(null);

  const items = useMemo<KanbanCardType[]>(() => {
    return allCards.map((card) =>
      overrides[card.id] ? { ...card, columnId: overrides[card.id] } : card,
    );
  }, [allCards, overrides]);

  const columnsIds = COLUMN_IDS;

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const handleDragStart = (event: DragStartEvent) => {
    setActiveId(event.active.id as string);
  };

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;

    if (!over) {
      setActiveId(null);
      return;
    }

    const activeCardId = active.id as string;
    const overId = over.id as string;

    if (activeCardId === overId) {
      setActiveId(null);
      return;
    }

    const isOverColumn = columnsIds.includes(overId as ColumnId);
    const overCard = items.find((item) => item.id === overId);

    if (isOverColumn) {
      setOverride(activeCardId, overId as ColumnId);
    } else if (overCard) {
      setOverride(activeCardId, overCard.columnId);
    }

    setActiveId(null);
  };

  const handleCardClick = (card: KanbanCardType) => {
    setDashboardTab("prs");
    setActiveRepo(card.activeRepo);
    setActivePr(card.pr);
    navigateTo("pr-review");
  };

  const isLoading = reposLoading || isLoadingPrs;

  if (isLoading) {
    return (
      <div className="flex h-full w-full gap-6 p-1">
        {COLUMNS.map((col) => (
          <div key={col.id} className="flex w-72 flex-col gap-3">
            <div className={cn("flex items-center gap-1.5 border-t-2 pt-2", col.borderColor)}>
              <Skeleton className="h-3.5 w-3.5 rounded-full" />
              <Skeleton className="h-3 w-24 rounded" />
            </div>
            <Skeleton className="h-24 w-full rounded-xl" />
            <Skeleton className="h-24 w-full rounded-xl" />
          </div>
        ))}
      </div>
    );
  }

  return (
    <DndContext sensors={sensors} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
      <div className="flex h-full w-full flex-col overflow-x-auto pb-4">
        <div className="flex h-full w-full gap-4 p-1">
          {COLUMNS.map((column) => {
            const columnCards = items.filter((item) => item.columnId === column.id);
            return (
              <div key={column.id} className="flex min-w-[220px] flex-1 flex-col gap-2">
                <div className={cn("flex items-center gap-1.5 border-t-2 pt-2", column.borderColor)}>
                  <ColumnIcon id={column.id} />
                  <span className="text-[11px] font-semibold uppercase tracking-wider text-zinc-400">
                    {column.title}
                  </span>
                  <span className="ml-auto text-[10px] text-zinc-600">{columnCards.length}</span>
                </div>

                <SortableContext items={columnCards.map((item) => item.id)}>
                  <div className="flex flex-1 flex-col gap-3">
                    <ColumnDroppable id={column.id}>
                      {columnCards.map((card) => (
                        <SortableKanbanCard key={card.id} card={card} compact={compact} onClick={handleCardClick} />
                      ))}
                    </ColumnDroppable>
                  </div>
                </SortableContext>
              </div>
            );
          })}
        </div>
      </div>

      {createPortal(
        <DragOverlay>
          {activeId ? <KanbanCardOverlay card={items.find((item) => item.id === activeId)!} compact={compact} /> : null}
        </DragOverlay>,
        document.body,
      )}
    </DndContext>
  );
}

function ColumnDroppable({ id, children }: { id: string; children: React.ReactNode }) {
  const { setNodeRef } = useDroppable({ id });
  return (
    <div ref={setNodeRef} className="flex flex-1 flex-col gap-3 min-h-[100px]">
      {children}
    </div>
  );
}

function SortableKanbanCard({ card, compact, onClick }: { card: KanbanCardType; compact: boolean; onClick: (card: KanbanCardType) => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: card.id,
    data: { ...card },
  });

  const style = {
    transform: CSS.Translate.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <Card
        className={cn(
          "group relative flex flex-col transition-all hover:border-zinc-700 hover:shadow-lg cursor-grab active:cursor-grabbing",
          compact ? "gap-1.5 p-2.5" : "gap-3 p-4",
        )}
        onClick={() => onClick(card)}
      >
        <CardContentInner card={card} compact={compact} />
      </Card>
    </div>
  );
}

function KanbanCardOverlay({ card, compact }: { card: KanbanCardType; compact: boolean }) {
  return (
    <Card className={cn("flex flex-col shadow-xl cursor-grabbing scale-105 rotate-2", compact ? "gap-1.5 p-2.5" : "gap-3 p-4")}>
      <CardContentInner card={card} compact={compact} />
    </Card>
  );
}

function CardContentInner({ card, compact }: { card: KanbanCardType; compact: boolean }) {
  const ciStatus = card.pr.ci_status;

  if (compact) {
    return (
      <div className="flex items-center gap-2 min-w-0">
        <span className="shrink-0 rounded bg-zinc-800 px-1.5 py-0.5 text-[10px] font-medium text-zinc-400">
          #{card.pr.number}
        </span>
        <span className="truncate text-xs font-semibold text-zinc-100">{card.title}</span>
        <span className="ml-auto shrink-0 text-[10px] text-zinc-600">{card.repo.split("/")[1]}</span>
        {ciStatus && (
          <span
            className={cn(
              "shrink-0 rounded px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider",
              ciStatus === "success"
                ? "bg-emerald-500/10 text-emerald-500"
                : ciStatus === "failure"
                  ? "bg-red-500/10 text-red-500"
                  : "bg-amber-500/10 text-amber-500",
            )}
          >
            {ciStatus}
          </span>
        )}
      </div>
    );
  }

  return (
    <>
      <div className="flex justify-between items-start gap-2">
        <span className="rounded bg-zinc-800 px-1.5 py-0.5 text-[10px] font-medium text-zinc-400">
          #{card.pr.number}
        </span>
        {ciStatus && (
          <span
            className={cn(
              "rounded px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider",
              ciStatus === "success"
                ? "bg-emerald-500/10 text-emerald-500"
                : ciStatus === "failure"
                  ? "bg-red-500/10 text-red-500"
                  : "bg-amber-500/10 text-amber-500",
            )}
          >
            {ciStatus}
          </span>
        )}
      </div>

      <div className="space-y-1">
        <h4 className="font-semibold text-zinc-100 line-clamp-2">{card.title}</h4>
        <p className="text-xs text-zinc-500">{card.repo}</p>
      </div>

      <div className="mt-2 flex items-center justify-between border-t border-zinc-800/50 pt-3">
        <div className="flex items-center gap-1.5 text-xs font-medium text-zinc-500">
          <Calendar size={12} />
          {card.date}
        </div>

        {card.author && (
          <Avatar className="h-5 w-5 border-none bg-purple-600">
            <AvatarFallback className="bg-purple-600 text-[10px] font-bold text-white">
              {card.author.charAt(0).toUpperCase()}
            </AvatarFallback>
          </Avatar>
        )}
      </div>
    </>
  );
}
