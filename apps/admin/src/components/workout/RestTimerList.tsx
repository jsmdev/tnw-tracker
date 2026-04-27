interface RestTimerRow {
  id: string;
  timer_type: string;
  duration_seconds: number;
  started_at: string;
  ends_at: string;
  is_active: boolean;
}

interface Props {
  timers: RestTimerRow[];
}

function timerTypeLabel(type: string) {
  return type === "between_sets"
    ? "Entre series"
    : type === "between_exercises"
      ? "Entre ejercicios"
      : type;
}

function formatSeconds(s: number) {
  const m = Math.floor(s / 60);
  const sec = s % 60;
  return m > 0 ? `${m}m ${sec}s` : `${sec}s`;
}

export function RestTimerList({ timers }: Props) {
  if (timers.length === 0) {
    return <p className="text-sm text-gray-400">No hay timers de descanso registrados.</p>;
  }

  return (
    <table className="w-full text-xs text-left">
      <thead>
        <tr className="text-gray-400 border-b border-gray-100">
          <th className="pb-1 pr-4 font-medium">Tipo</th>
          <th className="pb-1 pr-4 font-medium">Duración</th>
          <th className="pb-1 pr-4 font-medium">Inicio</th>
          <th className="pb-1 font-medium">Estado</th>
        </tr>
      </thead>
      <tbody>
        {timers.map((t) => {
          const actualDuration = Math.round(
            (new Date(t.ends_at).getTime() - new Date(t.started_at).getTime()) / 1000
          );
          const wasSkipped = !t.is_active && actualDuration < t.duration_seconds;

          return (
            <tr key={t.id} className="border-b border-gray-50">
              <td className="py-1 pr-4 text-gray-700">{timerTypeLabel(t.timer_type)}</td>
              <td className="py-1 pr-4">
                {formatSeconds(t.duration_seconds)}
                {wasSkipped && (
                  <span className="ml-1 text-gray-400">
                    (saltado en {formatSeconds(actualDuration)})
                  </span>
                )}
              </td>
              <td className="py-1 pr-4 text-gray-500">
                {new Date(t.started_at).toLocaleTimeString("es-ES", { timeStyle: "short" })}
              </td>
              <td className="py-1">
                {t.is_active ? (
                  <span className="text-green-600">Activo</span>
                ) : wasSkipped ? (
                  <span className="text-orange-500">Saltado</span>
                ) : (
                  <span className="text-gray-400">Completado</span>
                )}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}
