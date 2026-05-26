import {
  DndContext,
  DragOverEvent,
  DragOverlay,
  DragStartEvent,
  KeyboardSensor,
  PointerSensor,
  closestCorners,
  useDroppable,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import { SortableContext, sortableKeyboardCoordinates } from "@dnd-kit/sortable";
import { useVirtualizer } from "@tanstack/react-virtual";
import { createPortal } from "react-dom";
import { useMemo, useRef, useState } from "react";
import { EyeOff, MoreHorizontal, Plus } from "lucide-react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { StatusIcon } from "@/components/issues/issue-status";
import { useI18n } from "@/i18n/i18n";
import { useIssueKanbanStore } from "@/stores/useIssueKanbanStore";
import { useIssueViewStore } from "@/stores/issue-view-store";
import { KanbanHiddenRail } from "@/components/issues/kanban-hidden-rail";
import { KanbanCard, KanbanCardView, type IssueCardType } from "@/components/issues/kanban-card";
import { ISSUE_COLUMNS, issueToColumn } from "@/types/issue";
import type { IssueDto, IssueColumnId } from "@/types/issue";

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
  const parentRef = useRef<HTMLDivElement | null>(null);
  const setRefs = (el: HTMLDivElement | null) => {
    setNodeRef(el);
    parentRef.current = el;
  };
  const virtualizer = useVirtualizer({
    count: cards.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 96,
    overscan: 6,
  });

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
        ref={setRefs}
        className={cn(
          "min-h-0 flex-1 overflow-y-auto rounded-lg bg-zinc-100/50 p-2 transition-colors custom-scrollbar dark:bg-white/[0.02]",
          isOver && "bg-zinc-200/60 dark:bg-white/[0.05]",
        )}
      >
        <SortableContext items={cards.map((c) => c.id)}>
          <div style={{ height: virtualizer.getTotalSize(), position: "relative" }}>
            {virtualizer.getVirtualItems().map((virtualItem) => {
              const card = cards[virtualItem.index];
              return (
                <div
                  key={virtualItem.key}
                  data-index={virtualItem.index}
                  ref={virtualizer.measureElement}
                  style={{
                    position: "absolute",
                    top: 0,
                    left: 0,
                    width: "100%",
                    transform: `translateY(${virtualItem.start}px)`,
                    paddingBottom: 8,
                  }}
                >
                  <KanbanCard card={card} onSelect={onSelect} />
                </div>
              );
            })}
          </div>
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
  const [preview, setPreview] = useState<{ id: string; column: IssueColumnId } | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const COLUMN_ORDER: IssueColumnId[] = ["backlog", "todo", "in_progress", "done"];

  const cards: IssueCardType[] = useMemo(
    () =>
      issues.map((issue) => {
        const override = overrides[issue.id];
        const base = override && COLUMN_ORDER.includes(override) ? override : issueToColumn(issue);
        const columnId = preview && preview.id === issue.id ? preview.column : base;
        return { id: issue.id, issue, columnId };
      }),
    [issues, overrides, preview],
  );

  const resolveColumn = (overId: string): IssueColumnId | undefined =>
    COLUMN_ORDER.includes(overId as IssueColumnId)
      ? (overId as IssueColumnId)
      : cards.find((c) => c.id === overId)?.columnId;

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

  function onDragOver({ active, over }: DragOverEvent) {
    if (!over) return;
    const target = resolveColumn(over.id as string);
    if (target) setPreview({ id: active.id as string, column: target });
  }

  function onDragEnd() {
    if (preview) setOverride(preview.id, preview.column);
    setPreview(null);
    setDraggingId(null);
  }

  function onDragCancel() {
    setPreview(null);
    setDraggingId(null);
  }

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCorners}
      onDragStart={onDragStart}
      onDragOver={onDragOver}
      onDragEnd={onDragEnd}
      onDragCancel={onDragCancel}
    >
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
          {draggingCard && <KanbanCardView card={draggingCard} overlay />}
        </DragOverlay>,
        document.body,
      )}
    </DndContext>
  );
}
