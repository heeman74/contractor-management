"use client";

import { use } from "react";
import Link from "next/link";
import { toast } from "sonner";
import { AssignedJobsCard } from "./_components/assigned-jobs-card";
import { ContractorProfileSkeleton } from "./_components/contractor-profile-skeleton";
import { ContractorSidebar } from "./_components/contractor-sidebar";
import { WeeklyScheduleCard } from "./_components/weekly-schedule-card";
import { useContractorDetail } from "./_hooks/use-contractor-detail";

export default function ContractorProfilePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id: contractorId } = use(params);
  const {
    contractor,
    jobs,
    weeklySchedule,
    isLoading,
    usersError,
    activeJobsCount,
    hoursThisWeek,
    mostCommonTrade,
    initials,
    hasSchedule,
  } = useContractorDetail(contractorId);

  if (usersError) {
    toast.error("Failed to load contractor profile. Please refresh the page.", {
      duration: Infinity,
    });
  }

  if (isLoading) {
    return (
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <ContractorProfileSkeleton />
      </div>
    );
  }

  const headerName = contractor
    ? `${contractor.first_name ?? ""} ${contractor.last_name ?? ""}`.trim() ||
      contractor.email
    : "Contractor Profile";

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="space-y-1">
        <Link
          href="/contractors"
          className="text-sm text-gray-500 hover:text-gray-700 inline-flex items-center gap-1"
        >
          ← Back to Contractors
        </Link>
        <h1 className="text-xl font-semibold text-gray-900">{headerName}</h1>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[1fr_360px] gap-8">
        <div className="space-y-6">
          <WeeklyScheduleCard
            contractorId={contractorId}
            weeklySchedule={weeklySchedule}
            hasSchedule={hasSchedule}
          />
          <AssignedJobsCard jobs={jobs} />
        </div>

        <ContractorSidebar
          contractor={contractor}
          initials={initials}
          mostCommonTrade={mostCommonTrade}
          activeJobsCount={activeJobsCount}
          hoursThisWeek={hoursThisWeek}
        />
      </div>
    </div>
  );
}
