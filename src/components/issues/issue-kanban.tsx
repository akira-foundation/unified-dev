import {
  DndContext,
  DragEndEvent,
  DragOverlay,
  DragStartEvent,
  KeyboardSensor,
  PointerSensor,
  useDroppable,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import { SortableContext, sortableKeyboardCoordinates, useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { createPortal } from "react-dom";
import { useMemo, useState } from "react";
import { EyeOff, FolderGit2, GitPullRequest, MoreHorizontal, Plus } from "lucide-react";

import { Card } from "@/components/ui/card";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { StatusIcon } from "@/components/issues/issue-status";
import { useI18n } from "@/i18n/i18n";
import { formatRelativeDate } from "@/components/repos/pr-item";
import { useIssueKanbanStore } from "@/stores/useIssueKanbanStore";
import { useIssueViewStore } from "@/stores/issue-view-store";
import { KanbanHiddenRail } from "@/components/issues/kanban-hidden-rail";
import { ISSUE_COLUMNS, issueToColumn } from "@/types/issue";
import type { IssueDto, IssueColumnId } from "@/types/issue";

// ── card ─────────────────────────────────────────────────────────────────────

interface IssueCardType {
  id: string;
  issue: IssueDto;
  columnId: IssueColumnId;
}

function IssueCard({
  card,
  isDragging = false,
  onSelect,
}: {
  card: IssueCardType;
  isDragging?: boolean;
  onSelect?: (issue: IssueDto) => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition } = useSortable({ id: card.id });
  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0 : 1,
  };

  function handleClick() {
    onSelect?.(card.issue);
  }

  const issue = card.issue;
  const prNumber = issue.linkedPrNumbers[0];

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <Card
        className="flex cursor-pointer flex-col gap-2 border-zinc-200 bg-white p-2.5 transition-colors hover:border-zinc-300 dark:border-zinc-800 dark:bg-zinc-900/40 dark:hover:border-zinc-700"
        onClick={handleClick}
      >
        <div className="flex items-center justify-between">
          <span className="text-[11px] tabular-nums text-zinc-500">#{issue.number}</span>
          {issue.assignees[0] ? (
            <span
              className="flex h-5 w-5 items-center justify-center rounded-full bg-zinc-200 text-[9px] font-semibold text-zinc-600 dark:bg-zinc-700 dark:text-zinc-300"
              title={issue.assignees.join(", ")}
            >
              {issue.assignees[0].slice(0, 2).toUpperCase()}
            </span>
          ) : (
            <span className="h-5 w-5 rounded-full border border-dashed border-zinc-300 dark:border-zinc-700" />
          )}
        </div>

        <div className="flex items-start gap-2">
          <StatusIcon column={card.columnId} className="mt-0.5" />
          <span className="line-clamp-2 text-[13px] font-medium leading-snug text-zinc-800 dark:text-zinc-100">
            {issue.title}
          </span>
        </div>

        <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1 text-[10px] text-zinc-500 dark:text-zinc-400">
          <span className="inline-flex max-w-[130px] items-center gap-1 truncate">
            <FolderGit2 className="h-3 w-3 shrink-0" />
            {issue.repoName}
          </span>
          {prNumber !== undefined && (
            <span className="inline-flex items-center gap-0.5 text-purple-500">
              <GitPullRequest className="h-3 w-3" />#{prNumber}
            </span>
          )}
          {issue.labels.slice(0, 2).map((label) => (
            <span key={label} className="inline-flex max-w-[120px] items-center gap-1 truncate">
              <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-zinc-400 dark:bg-zinc-500" />
              {label}
            </span>
          ))}
        </div>

        <span className="text-[10px] text-zinc-400 dark:text-zinc-500">
          Created {formatRelativeDate(issue.createdAt)}
        </span>
      </Card>
    </div>
  );
}

// ── droppable column ──────────────────────────────────────────────────────────

function IssueColumn({
  id,
  title,
  cards,
  onSelect,
  onAdd,
  onHide,
}: {
  id: IssueColumnId;
  title: string;
  cards: IssueCardType[];
  onSelect?: (issue: IssueDto) => void;
  onAdd?: () => void;
  onHide?: () => void;
}) {
  const { setNodeRef, isOver } = useDroppable({ id });
  const { t } = useI18n();

  return (
    <div className="flex h-full w-[300px] shrink-0 flex-col">
      <div className="flex items-center gap-2 px-1 pb-2">
        <StatusIcon column={id} />
        <span className="text-[13px] font-semibold text-zinc-700 dark:text-zinc-200">{title}</span>
        <span className="text-[12px] text-zinc-500">{cards.length}</span>
        <div className="ml-auto flex items-center gap-0.5">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <button className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200">
                <MoreHorizontal className="h-3.5 w-3.5" />
              </button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={onHide}>
                <EyeOff className="mr-2 h-4 w-4" />
                {t("issues.kanban.hideColumn")}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
          <button
            onClick={onAdd}
            className="flex h-6 w-6 items-center justify-center rounded text-zinc-400 transition-colors hover:bg-zinc-200 hover:text-zinc-700 dark:hover:bg-zinc-700 dark:hover:text-zinc-200"
          >
            <Plus className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
      <div
        ref={setNodeRef}
        className={cn(
          "flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto rounded-lg bg-zinc-100/50 p-2 transition-colors custom-scrollbar dark:bg-white/[0.02]",
          isOver && "bg-zinc-200/60 dark:bg-white/[0.05]",
        )}
      >
        <SortableContext items={cards.map((c) => c.id)}>
          {cards.map((card) => (
            <IssueCard key={card.id} card={card} onSelect={onSelect} />
          ))}
        </SortableContext>
        <button
          onClick={onAdd}
          className="flex items-center gap-1.5 rounded-md px-2 py-1.5 text-[12px] text-zinc-500 transition-colors hover:bg-zinc-200/70 hover:text-zinc-700 dark:hover:bg-white/[0.04] dark:hover:text-zinc-200"
        >
          <Plus className="h-3.5 w-3.5" />
          {t("issues.kanban.addIssue")}
        </button>
      </div>
    </div>
  );
}

// ── main board ────────────────────────────────────────────────────────────────

export function IssueKanban({
  issues,
  onSelect,
  onNewIssue,
}: {
  issues: IssueDto[];
  onSelect?: (issue: IssueDto) => void;
  onNewIssue?: () => void;
}) {
  const { overrides, setOverride } = useIssueKanbanStore();
  const hiddenColumns = useIssueViewStore((s) => s.hiddenColumns);
  const hideColumn = useIssueViewStore((s) => s.hideColumn);
  const showColumn = useIssueViewStore((s) => s.showColumn);
  const [draggingId, setDraggingId] = useState<string | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const COLUMN_ORDER: IssueColumnId[] = ["backlog", "todo", "in_progress", "done"];

  const cards: IssueCardType[] = useMemo(
    () =>
      issues.map((issue) => {
        const override = overrides[issue.id];
        const columnId = override && COLUMN_ORDER.includes(override) ? override : issueToColumn(issue);
        return { id: issue.id, issue, columnId };
      }),
    [issues, overrides],
  );

  const columnCards = useMemo(() => {
    const map: Record<IssueColumnId, IssueCardType[]> = {
      backlog: [],
      todo: [],
      in_progress: [],
      done: [],
    };
    for (const card of cards) {
      (map[card.columnId] ?? map.backlog).push(card);
    }
    return map;
  }, [cards]);

  const draggingCard = draggingId ? cards.find((c) => c.id === draggingId) : null;

  function onDragStart({ active }: DragStartEvent) {
    setDraggingId(active.id as string);
  }

  function onDragEnd({ active, over }: DragEndEvent) {
    setDraggingId(null);
    if (!over) return;
    const newColumn = over.id as IssueColumnId;
    const dragged = cards.find((c) => c.id === (active.id as string));
    if (dragged && newColumn !== dragged.columnId) {
      setOverride(active.id as string, newColumn);
    }
  }

  return (
    <DndContext sensors={sensors} onDragStart={onDragStart} onDragEnd={onDragEnd}>
      <div className="flex h-full gap-4 overflow-x-auto pb-1">
        {COLUMN_ORDER.filter((id) => !hiddenColumns.includes(id)).map((id) => {
          const col = ISSUE_COLUMNS.find((c) => c.id === id)!;
          return (
            <IssueColumn
              key={id}
              id={id}
              title={col.label}
              cards={columnCards[id]}
              onSelect={onSelect}
              onAdd={onNewIssue}
              onHide={() => hideColumn(id)}
            />
          );
        })}

        <KanbanHiddenRail
          ids={COLUMN_ORDER.filter((id) => hiddenColumns.includes(id))}
          counts={{
            backlog: columnCards.backlog.length,
            todo: columnCards.todo.length,
            in_progress: columnCards.in_progress.length,
            done: columnCards.done.length,
          }}
          onShow={showColumn}
        />
      </div>
      {createPortal(
        <DragOverlay>
          {draggingCard && <IssueCard card={draggingCard} isDragging />}
        </DragOverlay>,
        document.body,
      )}
    </DndContext>
  );
}
