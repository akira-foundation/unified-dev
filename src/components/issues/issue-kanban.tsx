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
import { CircleDot, Circle, CheckCircle2, XCircle } from "lucide-react";

import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { LabelBadgeSmall } from "@/components/issues/label-badge";
import { useIssueKanbanStore } from "@/stores/useIssueKanbanStore";
import { ISSUE_COLUMNS, issueToColumn } from "@/types/issue";
import type { IssueDto, IssueColumnId } from "@/types/issue";

// ── column icon ──────────────────────────────────────────────────────────────

function ColumnIcon({ id }: { id: IssueColumnId }) {
  const cls = "h-3.5 w-3.5";
  if (id === "backlog") return <Circle className={cn(cls, "text-zinc-400")} />;
  if (id === "todo") return <CircleDot className={cn(cls, "text-blue-400")} />;
  if (id === "in_progress") return <CircleDot className={cn(cls, "text-amber-400")} />;
  if (id === "done") return <CheckCircle2 className={cn(cls, "text-emerald-400")} />;
  return <XCircle className={cn(cls, "text-zinc-500")} />;
}

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

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <Card
        className="cursor-pointer border-zinc-800 bg-zinc-900/60 p-3 hover:border-zinc-700 hover:bg-zinc-900"
        onClick={handleClick}
      >
        <div className="mb-1.5 flex items-start justify-between gap-2">
          <div className="flex min-w-0 items-start gap-2">
            <span className="line-clamp-2 text-xs font-medium leading-snug text-white">
              {card.issue.title}
            </span>
            <span
              className={`shrink-0 rounded-[6px] px-1.5 py-0.5 text-[10px] font-medium ${
                card.issue.syncWithProvider
                  ? "bg-emerald-500/10 text-emerald-400"
                  : "bg-zinc-500/10 text-zinc-400"
              }`}
            >
              {card.issue.syncWithProvider ? "synced" : "local"}
            </span>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-[10px] text-zinc-500">
            #{card.issue.number}
          </span>
          {card.issue.labels.slice(0, 2).map((label) => (
            <LabelBadgeSmall key={label} name={label} />
          ))}
          {card.issue.assignees.length > 0 && (
            <span className="ml-auto text-[10px] text-zinc-500">
              @{card.issue.assignees[0]}
            </span>
          )}
        </div>
      </Card>
    </div>
  );
}

// ── droppable column ──────────────────────────────────────────────────────────

function IssueColumn({
  id,
  title,
  cards,
  borderColor,
  onSelect,
}: {
  id: IssueColumnId;
  title: string;
  cards: IssueCardType[];
  borderColor: string;
  onSelect?: (issue: IssueDto) => void;
}) {
  const { setNodeRef, isOver } = useDroppable({ id });

  return (
    <div className="flex min-w-[220px] flex-1 flex-col gap-2">
      <div className={cn("flex items-center gap-1.5 border-t-2 pt-2", borderColor)}>
        <ColumnIcon id={id} />
        <span className="text-[11px] font-semibold uppercase tracking-wider text-zinc-400">
          {title}
        </span>
        <span className="ml-auto text-[10px] text-zinc-600">{cards.length}</span>
      </div>
      <div
        ref={setNodeRef}
        className={cn(
          "flex flex-col gap-2 rounded-md p-1 transition-colors min-h-[60px]",
          isOver && "bg-zinc-800/40",
        )}
      >
        <SortableContext items={cards.map((c) => c.id)}>
          {cards.map((card) => (
            <IssueCard key={card.id} card={card} onSelect={onSelect} />
          ))}
        </SortableContext>
      </div>
    </div>
  );
}

// ── main board ────────────────────────────────────────────────────────────────

export function IssueKanban({
  issues,
  onSelect,
}: {
  issues: IssueDto[];
  onSelect?: (issue: IssueDto) => void;
}) {
  const { overrides, setOverride } = useIssueKanbanStore();
  const [draggingId, setDraggingId] = useState<string | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const COLUMNS_CONFIG: { id: IssueColumnId; borderColor: string }[] = [
    { id: "backlog",     borderColor: "border-t-zinc-500"    },
    { id: "todo",        borderColor: "border-t-blue-500"    },
    { id: "in_progress", borderColor: "border-t-amber-500"   },
    { id: "done",        borderColor: "border-t-emerald-500" },
  ];

  const cards: IssueCardType[] = useMemo(
    () =>
      issues.map((issue) => ({
        id: issue.id,
        issue,
        columnId: overrides[issue.id] ?? issueToColumn(issue),
      })),
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
      map[card.columnId].push(card);
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
      <div className="flex gap-4 overflow-x-auto pb-4">
        {COLUMNS_CONFIG.map(({ id, borderColor }) => {
          const col = ISSUE_COLUMNS.find((c) => c.id === id)!;
          return (
            <IssueColumn
              key={id}
              id={id}
              title={col.label}
              cards={columnCards[id]}
              borderColor={borderColor}
              onSelect={onSelect}
            />
          );
        })}
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
