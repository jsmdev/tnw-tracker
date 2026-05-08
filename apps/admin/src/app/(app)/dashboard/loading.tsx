export default function DashboardLoading() {
  return (
    <div className="flex min-h-screen">
      {/* Sidebar skeleton */}
      <aside className="w-56 shrink-0 bg-white border-r border-gray-200">
        <div className="px-6 py-5 border-b border-gray-200">
          <div className="h-5 w-28 bg-gray-200 rounded animate-pulse" />
        </div>
        <div className="px-3 py-4 space-y-2">
          {Array.from({ length: 7 }).map((_, i) => (
            <div key={i} className="h-9 bg-gray-100 rounded-lg animate-pulse" />
          ))}
        </div>
      </aside>

      {/* Main con header skeleton + content stub */}
      <div className="flex-1 flex flex-col">
        <div className="bg-white border-b border-gray-200 px-6 py-3 flex items-center justify-between">
          <div className="h-4 w-48 bg-gray-200 rounded animate-pulse" />
          <div className="h-4 w-24 bg-gray-200 rounded animate-pulse" />
        </div>
        <main className="flex-1 p-8 space-y-4">
          <div className="h-8 w-1/3 bg-gray-200 rounded animate-pulse" />
          <div className="h-32 bg-gray-100 rounded-xl animate-pulse" />
          <div className="h-32 bg-gray-100 rounded-xl animate-pulse" />
        </main>
      </div>
    </div>
  );
}
