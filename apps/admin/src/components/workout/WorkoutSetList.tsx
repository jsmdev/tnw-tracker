interface ExerciseSet {
  id: string;
  set_number: number;
  reps: number | null;
  weight: number | null;
  weight_unit: string;
  rpe: number | null;
  is_warmup: boolean;
  is_personal_record: boolean;
  completed_at: string | null;
}

interface WorkoutExercise {
  id: string;
  order_index: number;
  exercise: { name: string; category: string } | null;
  exercise_sets: ExerciseSet[];
}

interface Props {
  workoutExercises: WorkoutExercise[];
}

function formatWeight(weight: number | null, unit: string) {
  if (weight == null) return "—";
  return `${weight} ${unit}`;
}

export function WorkoutSetList({ workoutExercises }: Props) {
  if (workoutExercises.length === 0) {
    return <p className="text-sm text-gray-500">Sin ejercicios registrados.</p>;
  }

  return (
    <div className="space-y-6">
      {workoutExercises.map((we) => (
        <div key={we.id}>
          <h3 className="text-sm font-semibold text-gray-800 mb-2">
            {we.exercise?.name ?? "Ejercicio eliminado"}
            <span className="ml-2 text-xs font-normal text-gray-400">{we.exercise?.category}</span>
          </h3>

          {we.exercise_sets.length === 0 ? (
            <p className="text-xs text-gray-400">Sin series.</p>
          ) : (
            <table className="w-full text-xs text-left">
              <thead>
                <tr className="text-gray-400 border-b border-gray-100">
                  <th className="pb-1 pr-4 font-medium">#</th>
                  <th className="pb-1 pr-4 font-medium">Reps</th>
                  <th className="pb-1 pr-4 font-medium">Peso</th>
                  <th className="pb-1 pr-4 font-medium">RPE</th>
                  <th className="pb-1 font-medium">Notas</th>
                </tr>
              </thead>
              <tbody>
                {we.exercise_sets.map((s) => (
                  <tr key={s.id} className="border-b border-gray-50">
                    <td className="py-1 pr-4 text-gray-500">
                      {s.set_number}
                      {s.is_warmup && <span className="ml-1 text-yellow-500">C</span>}
                    </td>
                    <td className="py-1 pr-4">{s.reps ?? "—"}</td>
                    <td className="py-1 pr-4">{formatWeight(s.weight, s.weight_unit)}</td>
                    <td className="py-1 pr-4">{s.rpe ?? "—"}</td>
                    <td className="py-1">
                      {s.is_personal_record && (
                        <span className="inline-flex items-center gap-1 text-amber-600 font-semibold">
                          PR
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      ))}
    </div>
  );
}
