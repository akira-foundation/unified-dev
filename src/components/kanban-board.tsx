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
import { SortableContext, arrayMove, sortableKeyboardCoordinates, useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { Calendar, MoreVertical, Plus } from "lucide-react";
import { createPortal } from "react-dom";
import { useMemo, useState } from "react";
import { useDroppable } from "@dnd-kit/core";

import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

interface KanbanCardType {
  id: string;
  title: string;
  repo: string;
  date: string;
  tag: string;
  priority?: "ALTA" | "MÉDIA" | "BAIXA";
  initial: string;
  columnId: "todo" | "inprogress" | "review" | "done";
}

const MOCK_DATA: KanbanCardType[] = [
  {
    id: "1",
    title: "Add org config schema",
    repo: "akira/infra",
    date: "12 Out",
    tag: "PR",
    priority: "ALTA",
    initial: "A",
    columnId: "todo",
  },
  {
    id: "2",
    title: "Update sync worker",
    repo: "akira/sync",
    date: "05 Nov",
    tag: "PR",
    priority: "ALTA",
    initial: "S",
    columnId: "todo",
  },
  {
    id: "3",
    title: "Tauri commands for orgs",
    repo: "akira/config",
    date: "15 Out",
    tag: "PR",
    priority: "MÉDIA",
    initial: "C",
    columnId: "inprogress",
  },
  {
    id: "4",
    title: "UI settings parity",
    repo: "akira/maintainer",
    date: "Hoje",
    tag: "PR",
    priority: "BAIXA",
    initial: "M",
    columnId: "inprogress",
  },
  {
    id: "5",
    title: "Fix build warnings",
    repo: "akira/ingest",
    date: "20 Out",
    tag: "PR",
    priority: "BAIXA",
    initial: "I",
    columnId: "review",
  },
  {
    id: "6",
    title: "Merge release PR",
    repo: "akira/release",
    date: "01 Nov",
    tag: "PR",
    priority: "ALTA",
    initial: "R",
    columnId: "done",
  },
];

const COLUMNS = [
  { id: "todo", title: "ABERTOS", color: "border-t-zinc-500" },
  { id: "inprogress", title: "BUILD OK", color: "border-t-blue-500" },
  { id: "review", title: "READY FOR MERGE", color: "border-t-amber-500" },
  { id: "done", title: "MERGE", color: "border-t-emerald-500" },
] as const;

export function KanbanBoard() {
  const [items, setItems] = useState<KanbanCardType[]>(MOCK_DATA);
  const [activeId, setActiveId] = useState<string | null>(null);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  const columnsIds = useMemo(() => COLUMNS.map((col) => col.id), []);

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

    const isActiveTask = items.some((item) => item.id === activeCardId);
    const isOverTask = items.some((item) => item.id === overId);
    const isOverColumn = columnsIds.includes(overId as any);

    setItems((currentItems) => {
      const activeIndex = currentItems.findIndex((item) => item.id === activeCardId);
      const overIndex = currentItems.findIndex((item) => item.id === overId);

      if (isActiveTask && isOverTask) {
        if (currentItems[activeIndex].columnId !== currentItems[overIndex].columnId) {
          currentItems[activeIndex].columnId = currentItems[overIndex].columnId;
        }
        return arrayMove(currentItems, activeIndex, overIndex);
      }

      if (isActiveTask && isOverColumn) {
        const activeItem = currentItems[activeIndex];
        if (activeItem.columnId !== overId) {
          activeItem.columnId = overId as any;
          return arrayMove(currentItems, activeIndex, activeIndex);
        }
      }

      return currentItems;
    });

    setActiveId(null);
  };

  return (
    <DndContext sensors={sensors} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
      <div className="flex h-full w-full flex-col overflow-x-auto pb-4">
        <div className="flex h-full w-full gap-6 p-1">
          {COLUMNS.map((column) => (
            <div key={column.id} className="flex w-80 flex-col gap-4">
              <div className={cn("flex items-center justify-between rounded-xl bg-[#1f1f22] px-4 py-3")}
              >
                <h3 className="text-xs font-bold uppercase tracking-wider text-zinc-300">{column.title}</h3>
                <span className="flex h-5 w-5 items-center justify-center rounded bg-zinc-800 text-[10px] font-bold text-zinc-400">
                  {items.filter((item) => item.columnId === column.id).length}
                </span>
              </div>

              <SortableContext items={items.filter((item) => item.columnId === column.id).map((item) => item.id)}>
                <div className="flex flex-1 flex-col gap-3">
                  <ColumnDroppable id={column.id}>
                    {items
                      .filter((item) => item.columnId === column.id)
                      .map((card) => (
                        <SortableKanbanCard key={card.id} card={card} />
                      ))}
                  </ColumnDroppable>
                </div>
              </SortableContext>

              <div className="h-10" />
            </div>
          ))}
        </div>
      </div>

      {createPortal(
        <DragOverlay>
          {activeId ? <KanbanCardOverlay card={items.find((item) => item.id === activeId)!} /> : null}
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

function SortableKanbanCard({ card }: { card: KanbanCardType }) {
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
      <Card className="group relative flex flex-col gap-3 transition-all hover:border-zinc-700 hover:shadow-lg cursor-grab active:cursor-grabbing p-4">
        <CardContentInner card={card} />
      </Card>
    </div>
  );
}

function KanbanCardOverlay({ card }: { card: KanbanCardType }) {
  return (
    <Card className="flex flex-col gap-3 shadow-xl cursor-grabbing scale-105 rotate-2 p-4">
      <CardContentInner card={card} />
    </Card>
  );
}

function CardContentInner({ card }: { card: KanbanCardType }) {
  return (
    <>
      {card.priority && (
        <div className="flex justify-between">
          <span
            className={cn(
              "rounded px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider",
              card.priority === "ALTA"
                ? "bg-red-500/10 text-red-500"
                : card.priority === "MÉDIA"
                  ? "bg-amber-500/10 text-amber-500"
                  : "bg-emerald-500/10 text-emerald-500",
            )}
          >
            {card.priority}
          </span>

          <div className="text-zinc-500">
            <MoreVertical size={14} />
          </div>
        </div>
      )}

      <div className="space-y-1">
        <h4 className="font-semibold text-zinc-100 line-clamp-2">{card.title}</h4>
        <p className="text-xs text-zinc-500">{card.repo}</p>
      </div>

      <div className="mt-2 flex items-center justify-between border-t border-zinc-800/50 pt-3">
        <div className="flex items-center gap-1.5 text-xs font-medium text-zinc-500">
          <Calendar size={12} />
          {card.date}
        </div>

        <div className="flex items-center gap-2">
          <span className="rounded bg-zinc-800 px-1.5 py-0.5 text-[10px] font-medium text-zinc-400">{card.tag}</span>
          <Avatar className="h-5 w-5 border-none bg-purple-600">
            <AvatarFallback className="bg-purple-600 text-[10px] font-bold text-white">{card.initial}</AvatarFallback>
          </Avatar>
        </div>
      </div>
    </>
  );
}
