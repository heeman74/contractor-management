import { useMemo, useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet, apiPut } from "@/lib/api-client";
import type { ContractorListItem, DateOverride, WeeklyBlock } from "@/types/api";
import {
  DEFAULT_CUSTOM_BLOCK,
  formatOverrideDate,
  parseOverrideDate,
  toIsoDate,
  weeklyScheduleToGrid,
  type CustomBlock,
} from "../_lib/schedule-overrides";

const NINETY_DAYS_MS = 90 * 86400000;

function contractorDisplayName(contractor: ContractorListItem | undefined): string {
  if (!contractor) return "...";
  const fullName = `${contractor.first_name ?? ""} ${contractor.last_name ?? ""}`.trim();
  return fullName || contractor.email;
}

interface SaveOverrideArgs {
  date: string;
  isUnavail: boolean;
  blocks: { start_time: string; end_time: string }[] | null;
}

export function useContractorSchedule(contractorId: string) {
  const queryClient = useQueryClient();

  // Queries -----------------------------------------------------------------

  const { data: allUsers } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<ContractorListItem[]>("/api/v1/users/"),
  });
  const contractorName = contractorDisplayName(
    allUsers?.find((u) => u.id === contractorId)
  );

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

  const { today, ninetyDaysOut } = useMemo(() => {
    const now = new Date();
    return {
      today: now.toISOString().split("T")[0],
      ninetyDaysOut: new Date(now.getTime() + NINETY_DAYS_MS)
        .toISOString()
        .split("T")[0],
    };
  }, []);

  const { data: overrides, refetch: refetchOverrides } = useQuery({
    queryKey: ["date-overrides", contractorId],
    queryFn: () =>
      apiGet<DateOverride[]>(
        `/api/v1/scheduling/schedules/${contractorId}/overrides?date_from=${today}&date_to=${ninetyDaysOut}`
      ),
    enabled: !!contractorId,
  });

  const initialSchedule = useMemo(
    () => weeklyScheduleToGrid(weeklySchedule),
    [weeklySchedule]
  );

  const overrideDates = useMemo(
    () => overrides?.map((o) => parseOverrideDate(o.override_date)) ?? [],
    [overrides]
  );

  // Override form state ------------------------------------------------------

  const [selectedDate, setSelectedDate] = useState<Date | undefined>();
  const [isUnavailable, setIsUnavailable] = useState(true);
  const [customBlocks, setCustomBlocks] = useState<CustomBlock[]>([
    DEFAULT_CUSTOM_BLOCK,
  ]);
  const [showRemoveDialog, setShowRemoveDialog] = useState(false);

  const existingOverride = selectedDate
    ? overrides?.find((o) => o.override_date === toIsoDate(selectedDate))
    : undefined;

  function selectDate(date: Date | undefined) {
    setSelectedDate(date);
    if (!date) return;

    const existing = overrides?.find(
      (o) => o.override_date === toIsoDate(date)
    );
    if (existing && !existing.is_unavailable && existing.start_time && existing.end_time) {
      setIsUnavailable(false);
      setCustomBlocks([
        {
          startHour: existing.start_time.slice(0, 5),
          endHour: existing.end_time.slice(0, 5),
        },
      ]);
    } else {
      setIsUnavailable(existing?.is_unavailable ?? true);
      setCustomBlocks([DEFAULT_CUSTOM_BLOCK]);
    }
  }

  // Mutation ----------------------------------------------------------------

  const saveOverrideMutation = useMutation({
    mutationFn: ({ date, isUnavail, blocks }: SaveOverrideArgs) =>
      apiPut<DateOverride[]>(
        `/api/v1/scheduling/schedules/${contractorId}/overrides/${date}`,
        { is_unavailable: isUnavail, blocks }
      ),
    onSuccess: (_, { date }) => {
      toast.success(
        `Override saved for ${formatOverrideDate(parseOverrideDate(date))}.`
      );
      refetchOverrides();
      queryClient.invalidateQueries({
        queryKey: ["date-overrides", contractorId],
      });
    },
    onError: () =>
      toast.error("Failed to save override. Please try again.", {
        duration: Infinity,
      }),
  });

  function saveOverride() {
    if (!selectedDate) return;
    saveOverrideMutation.mutate({
      date: toIsoDate(selectedDate),
      isUnavail: isUnavailable,
      blocks: isUnavailable
        ? null
        : customBlocks.map((b) => ({
            start_time: b.startHour,
            end_time: b.endHour,
          })),
    });
  }

  function removeOverride() {
    if (!selectedDate) return;
    saveOverrideMutation.mutate({
      date: toIsoDate(selectedDate),
      isUnavail: false,
      blocks: [],
    });
    setShowRemoveDialog(false);
    setSelectedDate(undefined);
  }

  function addCustomBlock() {
    setCustomBlocks((prev) => [...prev, DEFAULT_CUSTOM_BLOCK]);
  }

  function updateCustomBlock(
    index: number,
    field: keyof CustomBlock,
    value: string
  ) {
    setCustomBlocks((prev) =>
      prev.map((b, i) => (i === index ? { ...b, [field]: value } : b))
    );
  }

  function removeCustomBlock(index: number) {
    setCustomBlocks((prev) => prev.filter((_, i) => i !== index));
  }

  function requestRemove(date: Date) {
    setSelectedDate(date);
    setShowRemoveDialog(true);
  }

  return {
    contractorName,
    scheduleLoading,
    scheduleError,
    initialSchedule,
    overrides,
    overrideDates,
    selectedDate,
    isUnavailable,
    setIsUnavailable,
    customBlocks,
    existingOverride,
    showRemoveDialog,
    setShowRemoveDialog,
    isSaving: saveOverrideMutation.isPending,
    selectDate,
    saveOverride,
    removeOverride,
    addCustomBlock,
    updateCustomBlock,
    removeCustomBlock,
    requestRemove,
  };
}
