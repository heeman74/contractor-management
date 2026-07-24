export function PageSkeleton() {
  return (
    <div className="space-y-6 animate-pulse">
      <div className="space-y-2">
        <div className="h-7 w-2/3 rounded bg-gray-200" />
        <div className="h-5 w-24 rounded-full bg-gray-200" />
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        <div className="space-y-6">
          <div className="rounded-xl bg-gray-100 h-48" />
          <div className="rounded-xl bg-gray-100 h-32" />
        </div>
        <div className="space-y-4">
          <div className="rounded-xl bg-gray-100 h-36" />
          <div className="rounded-xl bg-gray-100 h-32" />
          <div className="rounded-xl bg-gray-100 h-40" />
        </div>
      </div>
    </div>
  );
}
