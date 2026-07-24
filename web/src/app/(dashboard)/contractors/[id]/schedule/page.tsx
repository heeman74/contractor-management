"use client";

import { use } from "react";
import Link from "next/link";
import { CalendarIcon } from "lucide-react";
import { ScheduleGrid } from "@/components/crm/schedule-grid";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Calendar } from "@/components/ui/calendar";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { DateOverrideForm } from "./_components/date-override-form";
import { OverrideList } from "./_components/override-list";
import { RemoveOverrideDialog } from "./_components/remove-override-dialog";
import { useContractorSchedule } from "./_hooks/use-contractor-schedule";

export default function ScheduleEditorPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id: contractorId } = use(params);
  const schedule = useContractorSchedule(contractorId);

  return (
    <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
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
              {schedule.contractorName}
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem>
            <BreadcrumbPage>Schedule</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>

      <h1 className="text-2xl font-bold text-gray-900">Edit Schedule</h1>

      {/* Section 1: Weekly Working Hours */}
      <Card>
        <CardHeader>
          <CardTitle>Weekly Working Hours</CardTitle>
        </CardHeader>
        <CardContent>
          {schedule.scheduleError ? (
            <p className="text-sm text-destructive">
              Failed to load schedule. Please refresh the page.
            </p>
          ) : schedule.scheduleLoading ? (
            <Skeleton className="h-96 w-full" />
          ) : (
            <ScheduleGrid
              contractorId={contractorId}
              initialSchedule={schedule.initialSchedule}
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
          <div className="space-y-2">
            <p className="text-sm text-muted-foreground">
              Select a date to set a custom override. Highlighted dates have
              existing overrides.
            </p>
            <Calendar
              mode="single"
              selected={schedule.selectedDate}
              onSelect={schedule.selectDate}
              modifiers={{ hasOverride: schedule.overrideDates }}
              modifiersClassNames={{
                hasOverride: "bg-secondary text-foreground font-semibold",
              }}
              disabled={{ before: new Date() }}
            />
          </div>

          {schedule.selectedDate && (
            <DateOverrideForm
              selectedDate={schedule.selectedDate}
              isUnavailable={schedule.isUnavailable}
              onIsUnavailableChange={schedule.setIsUnavailable}
              customBlocks={schedule.customBlocks}
              onAddBlock={schedule.addCustomBlock}
              onUpdateBlock={schedule.updateCustomBlock}
              onRemoveBlock={schedule.removeCustomBlock}
              canRemoveOverride={!!schedule.existingOverride}
              isSaving={schedule.isSaving}
              onSave={schedule.saveOverride}
              onRequestRemove={() => schedule.setShowRemoveDialog(true)}
            />
          )}

          <OverrideList
            overrides={schedule.overrides}
            onRemove={schedule.requestRemove}
          />
        </CardContent>
      </Card>

      <RemoveOverrideDialog
        open={schedule.showRemoveDialog}
        onOpenChange={schedule.setShowRemoveDialog}
        selectedDate={schedule.selectedDate}
        onConfirm={schedule.removeOverride}
      />
    </div>
  );
}
