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
import { createPortal } from "react-dom";
import { useMemo, useState } from "react";
import { EyeOff, MoreHorizontal } from "lucide-react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { useI18n } from "@/i18n/i18n";
import { useKanbanStore } from "@/stores/useKanbanStore";
import { usePrViewStore } from "@/stores/pr-view-store";
import { PrCard, PrCardView } from "@/components/prs/pr-card";
import { PrHiddenRail } from "@/components/prs/pr-hidden-rail";
import { PrStatusIcon, PR_COLUMN_LABEL_KEY, PR_COLUMN_ORDER, type PrColumnId } from "@/lib/pr-column";
import type { PrCardType } from "@/hooks/usePrCards";

function PrColumn({
  id,
  title,
  cards,
  onSelect,
  onHide,
}: {
  id: PrColumnId;
  title: string;
  cards: PrCardType[];
  onSelect?: (card: PrCardType) => void;
  onHide?: () => void;
}) {
  const { setNodeRef, isOver } = useDroppable({ id });
  const { t } = useI18n();

  return (
    <div className="flex h-full w-[300px] shrink-0 flex-col">
      <div className="flex items-center gap-2 px-1 pb-2">
        <PrStatusIcon column={id} />
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
                {t("prs.kanban.hideColumn")}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
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
            <PrCard key={card.id} card={card} onSelect={onSelect} />
          ))}
        </SortableContext>
      </div>
    </div>
  );
}

export function PrKanban({ cards, onSelect }: { cards: PrCardType[]; onSelect?: (card: PrCardType) => void }) {
  const { t } = useI18n();
  const { overrides, setOverride } = useKanbanStore();
  const hiddenColumns = usePrViewStore((s) => s.hiddenColumns);
  const hideColumn = usePrViewStore((s) => s.hideColumn);
  const showColumn = usePrViewStore((s) => s.showColumn);
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [preview, setPreview] = useState<{ id: string; column: PrColumnId } | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const resolved: PrCardType[] = useMemo(
    () =>
      cards.map((card) => {
        const override = overrides[card.id];
        const base = override && PR_COLUMN_ORDER.includes(override) ? override : card.columnId;
        const columnId = preview && preview.id === card.id ? preview.column : base;
        return { ...card, columnId };
      }),
    [cards, overrides, preview],
  );

  const resolveColumn = (overId: string): PrColumnId | undefined =>
    PR_COLUMN_ORDER.includes(overId as PrColumnId)
      ? (overId as PrColumnId)
      : resolved.find((c) => c.id === overId)?.columnId;

  const columnCards = useMemo(() => {
    const map: Record<PrColumnId, PrCardType[]> = { todo: [], inprogress: [], review: [], done: [] };
    for (const card of resolved) {
      (map[card.columnId] ?? map.todo).push(card);
    }
    return map;
  }, [resolved]);

  const draggingCard = draggingId ? resolved.find((c) => c.id === draggingId) : null;

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
        {PR_COLUMN_ORDER.filter((id) => !hiddenColumns.includes(id)).map((id) => (
          <PrColumn
            key={id}
            id={id}
            title={t(PR_COLUMN_LABEL_KEY[id])}
            cards={columnCards[id]}
            onSelect={onSelect}
            onHide={() => hideColumn(id)}
          />
        ))}

        <PrHiddenRail
          ids={PR_COLUMN_ORDER.filter((id) => hiddenColumns.includes(id))}
          counts={{
            todo: columnCards.todo.length,
            inprogress: columnCards.inprogress.length,
            review: columnCards.review.length,
            done: columnCards.done.length,
          }}
          onShow={showColumn}
        />
      </div>
      {createPortal(
        <DragOverlay>{draggingCard && <PrCardView card={draggingCard} overlay />}</DragOverlay>,
        document.body,
      )}
    </DndContext>
  );
}
