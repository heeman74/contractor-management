import { TabButton } from "@/components/shared/list-tabs";
import { REQUESTS_TAB, STATUS_TABS } from "../_lib/job-list";

interface JobsStatusTabsProps {
  activeTab: string;
  onTabChange: (tab: string) => void;
  getTabCount: (tabValue: string) => number | undefined;
}

export function JobsStatusTabs({
  activeTab,
  onTabChange,
  getTabCount,
}: JobsStatusTabsProps) {
  return (
    <div className="flex items-center border-b border-gray-200">
      {STATUS_TABS.map((tab) => (
        <TabButton
          key={tab.value}
          label={tab.label}
          value={tab.value}
          activeTab={activeTab}
          count={getTabCount(tab.value)}
          onTabChange={onTabChange}
        />
      ))}
      <span className="mx-2 text-gray-300">|</span>
      <TabButton
        label="Requests"
        value={REQUESTS_TAB}
        activeTab={activeTab}
        count={getTabCount(REQUESTS_TAB)}
        onTabChange={onTabChange}
      />
    </div>
  );
}
