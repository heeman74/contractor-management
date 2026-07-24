import { Briefcase, Clock } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import type { ContractorListItem } from "@/types/api";

const SECTION_LABEL_CLASS =
  "text-xs font-semibold text-gray-500 uppercase tracking-wide";

function contractorDisplayName(contractor: ContractorListItem | undefined): string {
  if (!contractor) return "—";
  const fullName = `${contractor.first_name ?? ""} ${contractor.last_name ?? ""}`.trim();
  return fullName || contractor.email;
}

function ContactCard({
  contractor,
  initials,
}: {
  contractor: ContractorListItem | undefined;
  initials: string;
}) {
  return (
    <Card>
      <CardContent className="pt-6 space-y-4">
        <div className="flex items-center gap-3">
          <Avatar size="lg">
            <AvatarFallback>{initials}</AvatarFallback>
          </Avatar>
          <div>
            <p className="text-sm font-semibold text-gray-900">
              {contractorDisplayName(contractor)}
            </p>
            <p className="text-xs text-gray-500">{contractor?.email ?? "—"}</p>
          </div>
        </div>
        <Separator />
        <div className="space-y-2">
          <div>
            <p className="text-xs text-gray-500">Phone</p>
            <p className="text-sm text-gray-900">{contractor?.phone ?? "—"}</p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function TradeCard({ mostCommonTrade }: { mostCommonTrade: string | null }) {
  return (
    <Card>
      <CardContent className="pt-6 space-y-2">
        <p className={SECTION_LABEL_CLASS}>Trade</p>
        <Badge className="bg-gray-100 text-gray-700 border-0">
          {mostCommonTrade ?? "Contractor"}
        </Badge>
      </CardContent>
    </Card>
  );
}

function QuickStatsCard({
  activeJobsCount,
  hoursThisWeek,
}: {
  activeJobsCount: number;
  hoursThisWeek: number;
}) {
  return (
    <Card>
      <CardContent className="pt-6 space-y-4">
        <p className={SECTION_LABEL_CLASS}>Quick Stats</p>
        <div className="grid grid-cols-2 gap-4">
          <div className="flex flex-col gap-1">
            <div className="rounded-md bg-secondary p-2 w-fit">
              <Briefcase className="h-4 w-4 text-foreground" />
            </div>
            <p className="text-2xl font-bold text-gray-900">{activeJobsCount}</p>
            <p className="text-xs text-gray-500">Active Jobs</p>
          </div>
          <div className="flex flex-col gap-1">
            <div className="rounded-md bg-secondary p-2 w-fit">
              <Clock className="h-4 w-4 text-foreground" />
            </div>
            <p className="text-2xl font-bold text-gray-900">{hoursThisWeek}h</p>
            <p className="text-xs text-gray-500">Hours This Week</p>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

function AverageRatingCard() {
  return (
    <Card>
      <CardContent className="pt-6 space-y-2">
        <p className={SECTION_LABEL_CLASS}>Average Rating</p>
        <p className="text-sm text-gray-500">No ratings yet</p>
      </CardContent>
    </Card>
  );
}

interface ContractorSidebarProps {
  contractor: ContractorListItem | undefined;
  initials: string;
  mostCommonTrade: string | null;
  activeJobsCount: number;
  hoursThisWeek: number;
}

export function ContractorSidebar({
  contractor,
  initials,
  mostCommonTrade,
  activeJobsCount,
  hoursThisWeek,
}: ContractorSidebarProps) {
  return (
    <div className="space-y-4">
      <ContactCard contractor={contractor} initials={initials} />
      <TradeCard mostCommonTrade={mostCommonTrade} />
      <QuickStatsCard
        activeJobsCount={activeJobsCount}
        hoursThisWeek={hoursThisWeek}
      />
      <AverageRatingCard />
    </div>
  );
}
