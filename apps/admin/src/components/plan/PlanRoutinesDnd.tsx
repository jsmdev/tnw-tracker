"use client";
import { useState, useTransition } from "react";
import {
  DndContext,
  closestCenter,
  KeyboardSensor,
  PointerSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from "@dnd-kit/core";
import {
  SortableContext,
  sortableKeyboardCoordinates,
  useSortable,
  verticalListSortingStrategy,
  arrayMove,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { reorderPlanRoutinesAction, removeRoutineFromPlanAction } from "@/app/actions/plan";

interface PlanRoutineRow {
  id: string;
  order_index: number;
  routine: {
    id: string;
    name: string;
  };
}

interface Props {
  planId: string;
  initial: PlanRoutineRow[];
}

function SortableRow({ item, planId }: { item: PlanRoutineRow; planId: string }) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: item.id,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  function handleRemove() {
    setError(null);
    startTransition(async () => {
      const result = await removeRoutineFromPlanAction(item.id, planId);
      if (result?.error) setError(result.error);
    });
  }

  return (
    <li
      ref={setNodeRef}
      style={style}
      className="flex flex-col gap-1 bg-white border border-gray-200 rounded-lg px-4 py-3"
    >
      <div className="flex items-center gap-3">
        <button
          type="button"
          {...attributes}
          {...listeners}
          className="text-gray-300 hover:text-gray-500 cursor-grab active:cursor-grabbing touch-none shrink-0"
          aria-label="Arrastrar para reordenar"
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
            <circle cx="5" cy="4" r="1.5" />
            <circle cx="11" cy="4" r="1.5" />
            <circle cx="5" cy="8" r="1.5" />
            <circle cx="11" cy="8" r="1.5" />
            <circle cx="5" cy="12" r="1.5" />
            <circle cx="11" cy="12" r="1.5" />
          </svg>
        </button>

        <span className="text-xs font-medium text-gray-400 w-6 shrink-0">
          {item.order_index + 1}
        </span>

        <p className="flex-1 font-medium text-gray-900 text-sm truncate">{item.routine.name}</p>

        <button
          type="button"
          onClick={handleRemove}
          disabled={isPending}
          className="text-red-400 hover:text-red-600 text-sm font-medium disabled:opacity-50 shrink-0"
        >
          {isPending ? "..." : "Quitar"}
        </button>
      </div>
      {error && (
        <p role="alert" className="text-xs text-red-600">
          {error}
        </p>
      )}
    </li>
  );
}

export function PlanRoutinesDnd({ planId, initial }: Props) {
  const [items, setItems] = useState(initial);
  const [isPending, startTransition] = useTransition();

  const sensors = useSensors(
    useSensor(PointerSensor),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
  );

  function onDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over || active.id === over.id) return;

    const oldIndex = items.findIndex((i) => i.id === active.id);
    const newIndex = items.findIndex((i) => i.id === over.id);
    const next = arrayMove(items, oldIndex, newIndex).map((item, idx) => ({
      ...item,
      order_index: idx,
    }));

    setItems(next);
    startTransition(async () => {
      await reorderPlanRoutinesAction(
        planId,
        next.map((it) => ({ id: it.id, orderIndex: it.order_index }))
      );
    });
  }

  if (items.length === 0) {
    return (
      <p className="text-sm text-gray-400 py-4 text-center">
        Sin rutinas. Busca y añade una desde el campo de arriba.
      </p>
    );
  }

  return (
    <div className={isPending ? "opacity-70 pointer-events-none" : undefined}>
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
        <SortableContext items={items.map((i) => i.id)} strategy={verticalListSortingStrategy}>
          <ul className="space-y-2">
            {items.map((item) => (
              <SortableRow key={item.id} item={item} planId={planId} />
            ))}
          </ul>
        </SortableContext>
      </DndContext>
    </div>
  );
}
