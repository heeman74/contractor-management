import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { WeeklyBlock } from "@/types/api";

// day_of_week: 0 = Monday ... 6 = Sunday (backend convention)
const DAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

function formatTimeRange(blocks: WeeklyBlock[]): string {
  if (blocks.length === 0) return "";
  return [...blocks]
    .sort((a, b) => a.block_index - b.block_index)
    .map((block) => `${block.start_time.slice(0, 5)}–${block.end_time.slice(0, 5)}`)
    .join(", ");
}

interface WeeklyScheduleCardProps {
  contractorId: string;
  weeklySchedule: Record<string, WeeklyBlock[]> | undefined;
  hasSchedule: boolean;
}

export function WeeklyScheduleCard({
  contractorId,
  weeklySchedule,
  hasSchedule,
}: WeeklyScheduleCardProps) {
  const router = useRouter();

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-4">
        <CardTitle className="text-base font-semibold text-gray-900">
          Weekly Schedule
        </CardTitle>
        <Button
          size="sm"
          onClick={() => router.push(`/contractors/${contractorId}/schedule`)}
        >
          Edit Schedule
        </Button>
      </CardHeader>
      <CardContent>
        {!hasSchedule ? (
          <p className="text-sm text-gray-500">
            No working hours configured. Click Edit Schedule to set availability.
          </p>
        ) : (
          <div className="grid grid-cols-7 gap-1">
            {DAY_LABELS.map((label, dayIndex) => {
              const dayBlocks = weeklySchedule?.[String(dayIndex)] ?? [];
              const hasBlocks = dayBlocks.length > 0;
              return (
                <div key={dayIndex} className="flex flex-col items-center gap-1">
                  <span className="text-xs font-medium text-gray-500">{label}</span>
                  <div
                    className={`w-full rounded px-1 py-2 text-center ${
                      hasBlocks
                        ? "bg-secondary text-foreground"
                        : "bg-gray-100 text-gray-400"
                    }`}
                  >
                    {hasBlocks ? (
                      <span className="text-xs">{formatTimeRange(dayBlocks)}</span>
                    ) : (
                      <span className="text-xs">Off</span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
