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
import {
  reorderSessionExercisesAction,
  removeExerciseFromSessionAction,
} from "@/app/actions/session";

interface SessionExerciseRow {
  id: string;
  order_index: number;
  exercise: {
    id: string;
    name: string;
    category: string;
  };
  target_sets: number | null;
  target_reps: number | null;
  rest_between_sets_seconds: number;
  notes: string | null;
}

interface Props {
  sessionId: string;
  initial: SessionExerciseRow[];
}

function SortableRow({ item, sessionId }: { item: SessionExerciseRow; sessionId: string }) {
  const [isPending, startTransition] = useTransition();
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: item.id,
  });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  };

  function handleRemove() {
    startTransition(async () => {
      await removeExerciseFromSessionAction(item.id, sessionId);
    });
  }

  return (
    <li
      ref={setNodeRef}
      style={style}
      className="flex items-center gap-3 bg-white border border-gray-200 rounded-lg px-4 py-3"
    >
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

      <span className="text-xs font-medium text-gray-400 w-6 shrink-0">{item.order_index + 1}</span>

      <div className="flex-1 min-w-0">
        <p className="font-medium text-gray-900 text-sm truncate">{item.exercise.name}</p>
        <p className="text-xs text-gray-400">
          {[
            item.target_sets && `${item.target_sets} series`,
            item.target_reps && `${item.target_reps} reps`,
            item.rest_between_sets_seconds && `${item.rest_between_sets_seconds}s descanso`,
          ]
            .filter(Boolean)
            .join(" · ")}
        </p>
      </div>

      <span className="text-xs text-gray-400 shrink-0">{item.exercise.category}</span>

      <button
        type="button"
        onClick={handleRemove}
        disabled={isPending}
        className="text-red-400 hover:text-red-600 text-sm font-medium disabled:opacity-50 shrink-0"
      >
        {isPending ? "..." : "Quitar"}
      </button>
    </li>
  );
}

export function SessionExercisesDnd({ sessionId, initial }: Props) {
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
      await reorderSessionExercisesAction(
        sessionId,
        next.map((it) => ({ id: it.id, orderIndex: it.order_index }))
      );
    });
  }

  if (items.length === 0) {
    return (
      <p className="text-sm text-gray-400 py-4 text-center">
        Sin ejercicios. Busca y añade uno desde el campo de arriba.
      </p>
    );
  }

  return (
    <div className={isPending ? "opacity-70 pointer-events-none" : undefined}>
      <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
        <SortableContext items={items.map((i) => i.id)} strategy={verticalListSortingStrategy}>
          <ul className="space-y-2">
            {items.map((item) => (
              <SortableRow key={item.id} item={item} sessionId={sessionId} />
            ))}
          </ul>
        </SortableContext>
      </DndContext>
    </div>
  );
}
