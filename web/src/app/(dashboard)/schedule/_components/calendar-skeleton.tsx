"use client";

export function CalendarSkeleton() {
  return (
    <div className="animate-pulse">
      {/* Contractor lane header row */}
      <div className="flex border-b h-16">
        {/* Time axis placeholder */}
        <div className="w-12 bg-gray-100 border-r flex-shrink-0" />
        {/* Lane header blocks */}
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            className="flex-1 mx-1 rounded bg-gray-200 h-10 self-center"
          />
        ))}
      </div>

      {/* Time grid rows */}
      {Array.from({ length: 7 }).map((_, rowIndex) => (
        <div key={rowIndex} className="flex h-16 border-b">
          {/* Time label */}
          <div className="w-12 bg-gray-50 border-r flex-shrink-0" />
          {/* Event blocks with varying widths */}
          <div className="flex-1 relative">
            {rowIndex % 3 === 0 && (
              <div
                className="rounded-md bg-gray-200 h-10 absolute top-2"
                style={{ left: "5%", width: "20%" }}
              />
            )}
            {rowIndex % 3 === 1 && (
              <div
                className="rounded-md bg-gray-200 h-10 absolute top-2"
                style={{ left: "30%", width: "35%" }}
              />
            )}
            {rowIndex % 3 === 2 && (
              <div
                className="rounded-md bg-gray-200 h-8 absolute top-3"
                style={{ left: "60%", width: "15%" }}
              />
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
