"use client";

import { use, useMemo, useState } from "react";
import Link from "next/link";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { CalendarIcon } from "lucide-react";
import { toast } from "sonner";
import { apiGet, apiPut } from "@/lib/api-client";
import { ScheduleGrid } from "@/components/crm/schedule-grid";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { Calendar } from "@/components/ui/calendar";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import type { ContractorListItem, DateOverride, WeeklyBlock } from "@/types/api";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatDate(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function formatDisplayDate(date: Date): string {
  return date.toLocaleDateString(undefined, {
    year: "numeric",
    month: "long",
    day: "numeric",
  });
}

const HOUR_OPTIONS = Array.from({ length: 15 }, (_, i) => {
  const h = String(i + 6).padStart(2, "0");
  return `${h}:00`;
}); // "06:00" ... "20:00"

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

export default function ScheduleEditorPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id: contractorId } = use(params);
  const queryClient = useQueryClient();

  // ------ Data fetching ------

  const { data: allUsers } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<ContractorListItem[]>("/api/v1/users/"),
  });
  const contractor = allUsers?.find((u) => u.id === contractorId);
  const contractorName = contractor
    ? `${contractor.first_name ?? ""} ${contractor.last_name ?? ""}`.trim() ||
      contractor.email
    : "...";

  const {
    data: weeklySchedule,
    isLoading: scheduleLoading,
    isError: scheduleError,
  } = useQuery({
    queryKey: ["weekly-schedule", contractorId],
    queryFn: () =>
      apiGet<Record<string, WeeklyBlock[]>>(
        `/api/v1/scheduling/schedules/${contractorId}/weekly`
      ),
    enabled: !!contractorId,
  });

  const today = new Date().toISOString().split("T")[0];
  const ninetyDaysOut = new Date(Date.now() + 90 * 86400000)
    .toISOString()
    .split("T")[0];

  const { data: overrides, refetch: refetchOverrides } = useQuery({
    queryKey: ["date-overrides", contractorId],
    queryFn: () =>
      apiGet<DateOverride[]>(
        `/api/v1/scheduling/schedules/${contractorId}/overrides?date_from=${today}&date_to=${ninetyDaysOut}`
      ),
    enabled: !!contractorId,
  });

  // ------ Convert weekly schedule to ScheduleGrid initialSchedule ------

  const initialSchedule = useMemo(() => {
    const result: Record<number, number[]> = {};
    if (!weeklySchedule) return result;
    for (const [dayStr, blocks] of Object.entries(weeklySchedule)) {
      const day = parseInt(dayStr);
      const hours: number[] = [];
      for (const block of blocks) {
        const startHour = parseInt(block.start_time.split(":")[0]);
        const endHour = parseInt(block.end_time.split(":")[0]);
        for (let h = startHour; h < endHour; h++) {
          if (h >= 6 && h <= 20) hours.push(h);
        }
      }
      result[day] = hours;
    }
    return result;
  }, [weeklySchedule]);

  // ------ Date overrides state ------

  const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
  const [isUnavailable, setIsUnavailable] = useState(true);
  const [customBlocks, setCustomBlocks] = useState<
    { startHour: string; endHour: string }[]
  >([{ startHour: "09:00", endHour: "17:00" }]);
  const [showRemoveDialog, setShowRemoveDialog] = useState(false);

  // Compute which dates have overrides for calendar highlight
  const overrideDates = useMemo(
    () =>
      overrides?.map((o) => new Date(o.override_date + "T00:00:00")) ?? [],
    [overrides]
  );

  // Check if selected date already has an override
  const existingOverride = selectedDate
    ? overrides?.find((o) => o.override_date === formatDate(selectedDate))
    : undefined;

  // When a date is selected, pre-populate form from existing override if any
  function handleDateSelect(date: Date | undefined) {
    setSelectedDate(date);
    if (date) {
      const existing = overrides?.find(
        (o) => o.override_date === formatDate(date)
      );
      if (existing) {
        setIsUnavailable(existing.is_unavailable);
        // Build customBlocks from grouped override entries
        if (!existing.is_unavailable && existing.start_time && existing.end_time) {
          setCustomBlocks([
            {
              startHour: existing.start_time.slice(0, 5),
              endHour: existing.end_time.slice(0, 5),
            },
          ]);
        } else {
          setCustomBlocks([{ startHour: "09:00", endHour: "17:00" }]);
        }
      } else {
        setIsUnavailable(true);
        setCustomBlocks([{ startHour: "09:00", endHour: "17:00" }]);
      }
    }
  }

  // ------ Save override mutation ------

  const saveOverrideMutation = useMutation({
    mutationFn: async ({
      date,
      isUnavail,
      blocks,
    }: {
      date: string;
      isUnavail: boolean;
      blocks: { start_time: string; end_time: string }[] | null;
    }) => {
      return apiPut<DateOverride[]>(
        `/api/v1/scheduling/schedules/${contractorId}/overrides/${date}`,
        { is_unavailable: isUnavail, blocks }
      );
    },
    onSuccess: (_, { date }) => {
      toast.success(
        `Override saved for ${formatDisplayDate(new Date(date + "T00:00:00"))}.`
      );
      refetchOverrides();
      queryClient.invalidateQueries({
        queryKey: ["date-overrides", contractorId],
      });
    },
    onError: () => {
      toast.error("Failed to save override. Please try again.", {
        duration: Infinity,
      });
    },
  });

  function handleSaveOverride() {
    if (!selectedDate) return;
    saveOverrideMutation.mutate({
      date: formatDate(selectedDate),
      isUnavail: isUnavailable,
      blocks: isUnavailable
        ? null
        : customBlocks.map((b) => ({
            start_time: b.startHour,
            end_time: b.endHour,
          })),
    });
  }

  function handleRemoveOverride() {
    if (!selectedDate) return;
    saveOverrideMutation.mutate({
      date: formatDate(selectedDate),
      isUnavail: false,
      blocks: [],
    });
    setShowRemoveDialog(false);
    setSelectedDate(undefined);
  }

  function addCustomBlock() {
    setCustomBlocks((prev) => [
      ...prev,
      { startHour: "09:00", endHour: "17:00" },
    ]);
  }

  function updateCustomBlock(
    index: number,
    field: "startHour" | "endHour",
    value: string
  ) {
    setCustomBlocks((prev) =>
      prev.map((b, i) => (i === index ? { ...b, [field]: value } : b))
    );
  }

  function removeCustomBlock(index: number) {
    setCustomBlocks((prev) => prev.filter((_, i) => i !== index));
  }

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      {/* Breadcrumb */}
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            <BreadcrumbLink render={<Link href="/contractors" />}>
              Contractors
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem>
            <BreadcrumbLink render={<Link href={`/contractors/${contractorId}`} />}>
              {contractorName}
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem>
            <BreadcrumbPage>Schedule</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>

      {/* Page title */}
      <h1 className="text-2xl font-bold text-gray-900">Edit Schedule</h1>

      {/* Section 1: Weekly Working Hours */}
      <Card>
        <CardHeader>
          <CardTitle>Weekly Working Hours</CardTitle>
        </CardHeader>
        <CardContent>
          {scheduleError ? (
            <p className="text-sm text-destructive">
              Failed to load schedule. Please refresh the page.
            </p>
          ) : scheduleLoading ? (
            <Skeleton className="h-96 w-full" />
          ) : (
            <ScheduleGrid
              contractorId={contractorId}
              initialSchedule={initialSchedule}
            />
          )}
        </CardContent>
      </Card>

      {/* Section 2: Date Overrides */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <CalendarIcon className="h-5 w-5" />
            Date Overrides
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* Calendar */}
          <div className="space-y-2">
            <p className="text-sm text-muted-foreground">
              Select a date to set a custom override. Highlighted dates have
              existing overrides.
            </p>
            <Calendar
              mode="single"
              selected={selectedDate}
              onSelect={handleDateSelect}
              modifiers={{ hasOverride: overrideDates }}
              modifiersClassNames={{
                hasOverride: "bg-indigo-100 text-indigo-800 font-semibold",
              }}
              disabled={{ before: new Date() }}
            />
          </div>

          {/* Override form — shown when a date is selected */}
          {selectedDate && (
            <div className="border rounded-lg p-4 space-y-4">
              <p className="text-sm font-medium text-gray-900">
                Override for{" "}
                <span className="font-semibold">
                  {formatDisplayDate(selectedDate)}
                </span>
              </p>

              {/* Toggle: Unavailable all day vs Custom hours */}
              <div className="flex gap-4">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="override-type"
                    checked={isUnavailable}
                    onChange={() => setIsUnavailable(true)}
                    className="accent-indigo-600"
                  />
                  <span className="text-sm">Unavailable all day</span>
                </label>
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="override-type"
                    checked={!isUnavailable}
                    onChange={() => setIsUnavailable(false)}
                    className="accent-indigo-600"
                  />
                  <span className="text-sm">Custom hours</span>
                </label>
              </div>

              {/* Custom hours blocks */}
              {!isUnavailable && (
                <div className="space-y-3">
                  {customBlocks.map((block, index) => (
                    <div key={index} className="flex items-center gap-3">
                      <Select<string>
                        value={block.startHour}
                        onValueChange={(v) =>
                          v != null && updateCustomBlock(index, "startHour", v)
                        }
                      >
                        <SelectTrigger className="w-28">
                          <SelectValue placeholder="Start" />
                        </SelectTrigger>
                        <SelectContent>
                          {HOUR_OPTIONS.map((h) => (
                            <SelectItem key={h} value={h}>
                              {h}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <span className="text-sm text-muted-foreground">to</span>
                      <Select<string>
                        value={block.endHour}
                        onValueChange={(v) =>
                          v != null && updateCustomBlock(index, "endHour", v)
                        }
                      >
                        <SelectTrigger className="w-28">
                          <SelectValue placeholder="End" />
                        </SelectTrigger>
                        <SelectContent>
                          {HOUR_OPTIONS.map((h) => (
                            <SelectItem key={h} value={h}>
                              {h}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      {customBlocks.length > 1 && (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => removeCustomBlock(index)}
                          className="text-destructive hover:text-destructive"
                        >
                          Remove
                        </Button>
                      )}
                    </div>
                  ))}
                  <Button variant="outline" size="sm" onClick={addCustomBlock}>
                    Add block
                  </Button>
                </div>
              )}

              {/* Action buttons */}
              <div className="flex gap-3 pt-2">
                <Button
                  onClick={handleSaveOverride}
                  disabled={saveOverrideMutation.isPending}
                >
                  Save Override
                </Button>
                {existingOverride && (
                  <Button
                    variant="destructive"
                    onClick={() => setShowRemoveDialog(true)}
                    disabled={saveOverrideMutation.isPending}
                  >
                    Remove Override
                  </Button>
                )}
              </div>
            </div>
          )}

          {/* Existing overrides list */}
          <div className="space-y-2">
            <p className="text-sm font-semibold text-gray-700">
              Current Overrides
            </p>
            {!overrides || overrides.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                No date overrides set. Select a date above to add one.
              </p>
            ) : (
              <div className="space-y-2">
                {/* Deduplicate by override_date since the API returns one row per block */}
                {Array.from(
                  new Map(overrides.map((o) => [o.override_date, o])).values()
                ).map((override) => (
                  <div
                    key={override.override_date}
                    className="flex items-center justify-between rounded-md border px-4 py-2 text-sm"
                  >
                    <span className="text-gray-900">
                      {formatDisplayDate(
                        new Date(override.override_date + "T00:00:00")
                      )}
                    </span>
                    <span className="text-muted-foreground">
                      {override.is_unavailable
                        ? "Unavailable"
                        : override.start_time && override.end_time
                        ? `${override.start_time.slice(0, 5)} – ${override.end_time.slice(0, 5)}`
                        : "Custom hours"}
                    </span>
                    <Button
                      variant="ghost"
                      size="sm"
                      className="text-destructive hover:text-destructive"
                      onClick={() => {
                        setSelectedDate(
                          new Date(override.override_date + "T00:00:00")
                        );
                        setShowRemoveDialog(true);
                      }}
                    >
                      Remove
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* Remove override confirmation dialog */}
      <Dialog open={showRemoveDialog} onOpenChange={setShowRemoveDialog}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Remove override?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            This will delete the date override for{" "}
            {selectedDate ? formatDisplayDate(selectedDate) : "this date"}. The
            contractor&apos;s regular weekly schedule will apply.
          </p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setShowRemoveDialog(false)}
            >
              Cancel
            </Button>
            <Button variant="destructive" onClick={handleRemoveOverride}>
              Remove
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
