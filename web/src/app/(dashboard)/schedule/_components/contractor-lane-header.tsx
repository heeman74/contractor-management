"use client";

import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import type { ContractorResource } from "@/types/schedule";

interface ContractorLaneHeaderProps {
  resource: ContractorResource;
}

export function ContractorLaneHeader({ resource }: ContractorLaneHeaderProps) {
  const initials = resource.name.charAt(0).toUpperCase();

  return (
    <div className="flex flex-col items-center gap-1 py-2 px-1 min-w-[120px]">
      <Avatar className="h-8 w-8 rounded-full">
        {resource.avatarUrl ? (
          <AvatarImage src={resource.avatarUrl} alt={resource.name} />
        ) : null}
        <AvatarFallback>{initials}</AvatarFallback>
      </Avatar>
      <span className="text-sm font-medium text-gray-900 truncate max-w-[140px]">
        {resource.name}
      </span>
      {resource.tradeType && (
        <span className="text-xs text-gray-500">{resource.tradeType}</span>
      )}
    </div>
  );
}
