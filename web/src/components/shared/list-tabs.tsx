const ACTIVE_TAB_CLASSES =
  "border-b-2 border-gray-900 text-gray-900 font-semibold -mb-px";
const INACTIVE_TAB_CLASSES = "text-gray-500 hover:text-gray-700";

export interface StatusTab {
  label: string;
  value: string;
}

export function TabButton({
  label,
  value,
  activeTab,
  count,
  onTabChange,
}: {
  label: string;
  value: string;
  activeTab: string;
  count: number | undefined;
  onTabChange: (tab: string) => void;
}) {
  const isActive = activeTab === value;
  return (
    <button
      onClick={() => onTabChange(value)}
      className={`py-3 px-4 text-sm transition-colors whitespace-nowrap ${
        isActive ? ACTIVE_TAB_CLASSES : INACTIVE_TAB_CLASSES
      }`}
    >
      {label}
      {count !== undefined && (
        <span className="text-xs text-gray-400 ml-1">({count})</span>
      )}
    </button>
  );
}

interface ListStatusTabsProps {
  tabs: StatusTab[];
  activeTab: string;
  onTabChange: (tab: string) => void;
  getTabCount: (tabValue: string) => number | undefined;
}

export function ListStatusTabs({
  tabs,
  activeTab,
  onTabChange,
  getTabCount,
}: ListStatusTabsProps) {
  return (
    <div className="flex items-center border-b border-gray-200">
      {tabs.map((tab) => (
        <TabButton
          key={tab.value}
          label={tab.label}
          value={tab.value}
          activeTab={activeTab}
          count={getTabCount(tab.value)}
          onTabChange={onTabChange}
        />
      ))}
    </div>
  );
}
