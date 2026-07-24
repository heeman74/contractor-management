import { useQuery } from "@tanstack/react-query";
import { apiGet } from "@/lib/api-client";
import type { ContractorListItem, Job, WeeklyBlock } from "@/types/api";

export const ACTIVE_JOB_STATUSES = ["scheduled", "in_progress"];

export function getMostCommonTradeType(jobs: Job[]): string | null {
  if (jobs.length === 0) return null;
  const countsByTrade: Record<string, number> = {};
  for (const job of jobs) {
    if (job.trade_type) {
      countsByTrade[job.trade_type] = (countsByTrade[job.trade_type] ?? 0) + 1;
    }
  }
  const trades = Object.entries(countsByTrade);
  if (trades.length === 0) return null;
  return trades.sort((a, b) => b[1] - a[1])[0][0];
}

export function blockDurationMinutes(block: WeeklyBlock): number {
  const [startHour, startMinute] = block.start_time.split(":").map(Number);
  const [endHour, endMinute] = block.end_time.split(":").map(Number);
  const startTotal = startHour * 60 + startMinute;
  const endTotal = endHour * 60 + endMinute;
  return Math.max(0, endTotal - startTotal);
}

export function calcHoursThisWeek(
  weeklySchedule: Record<string, WeeklyBlock[]> | undefined
): number {
  if (!weeklySchedule) return 0;
  let totalMinutes = 0;
  for (const dayBlocks of Object.values(weeklySchedule)) {
    for (const block of dayBlocks) {
      totalMinutes += blockDurationMinutes(block);
    }
  }
  return Math.round((totalMinutes / 60) * 10) / 10;
}

export function getInitials(contractor: ContractorListItem | undefined): string {
  const first = (contractor?.first_name?.[0] ?? "").toUpperCase();
  const last = (contractor?.last_name?.[0] ?? "").toUpperCase();
  return `${first}${last}` || "?";
}

export function hasWorkingHours(
  weeklySchedule: Record<string, WeeklyBlock[]> | undefined
): boolean {
  return Boolean(
    weeklySchedule &&
      Object.values(weeklySchedule).some((blocks) => blocks.length > 0)
  );
}

export function useContractorDetail(contractorId: string) {
  const {
    data: allUsers,
    isLoading: usersLoading,
    isError: usersError,
  } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<ContractorListItem[]>("/api/v1/users/"),
  });
  const contractor = allUsers?.find((user) => user.id === contractorId);

  const { data: jobs, isLoading: jobsLoading } = useQuery({
    queryKey: ["contractor-jobs", contractorId],
    queryFn: () => apiGet<Job[]>(`/api/v1/jobs/?contractor_id=${contractorId}`),
    enabled: !!contractorId,
  });

  const { data: weeklySchedule, isLoading: scheduleLoading } = useQuery({
    queryKey: ["weekly-schedule", contractorId],
    queryFn: () =>
      apiGet<Record<string, WeeklyBlock[]>>(
        `/api/v1/scheduling/schedules/${contractorId}/weekly`
      ),
    enabled: !!contractorId,
  });

  const activeJobsCount =
    jobs?.filter((job) => ACTIVE_JOB_STATUSES.includes(job.status)).length ?? 0;

  return {
    contractor,
    jobs,
    weeklySchedule,
    isLoading: usersLoading || jobsLoading || scheduleLoading,
    usersError,
    activeJobsCount,
    hoursThisWeek: calcHoursThisWeek(weeklySchedule),
    mostCommonTrade: getMostCommonTradeType(jobs ?? []),
    initials: getInitials(contractor),
    hasSchedule: hasWorkingHours(weeklySchedule),
  };
}
