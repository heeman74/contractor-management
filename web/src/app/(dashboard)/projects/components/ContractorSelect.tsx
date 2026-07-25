"use client";

import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
} from "@/components/ui/select";
import type { ContractorMatch } from "@/types/projects";

interface ContractorSelectProps {
  value: string;
  onValueChange: (value: string) => void;
  specialtyContractors: ContractorMatch[];
  otherContractors: ContractorMatch[];
  hasContractors: boolean;
}

export function ContractorSelect({
  value,
  onValueChange,
  specialtyContractors,
  otherContractors,
  hasContractors,
}: ContractorSelectProps) {
  // Derive the trigger label from our own data instead of relying on Radix's
  // captured item text: when the trade changes, the contractors query refetches
  // and the items unmount, which clears Radix's cached text and makes it fall
  // back to showing the raw id. Looking the name up by id keeps it stable.
  const selectedContractor = [...specialtyContractors, ...otherContractors].find(
    (contractor) => contractor.id === value
  );

  return (
    <div className="flex flex-col gap-1.5">
      <Label>Contractor (optional)</Label>
      <Select value={value} onValueChange={(v) => onValueChange(v ?? "")}>
        <SelectTrigger className="w-full" data-testid="contractor-select">
          {selectedContractor ? (
            <span>{selectedContractor.name}</span>
          ) : (
            <span className="text-muted-foreground">Select contractor...</span>
          )}
        </SelectTrigger>
        <SelectContent>
          {specialtyContractors.length > 0 && (
            <>
              {specialtyContractors.map((c) => (
                <SelectItem key={c.id} value={c.id}>
                  {c.name}{" "}
                  <span className="text-xs text-muted-foreground">
                    (Specialty match)
                  </span>
                </SelectItem>
              ))}
              {otherContractors.length > 0 && (
                <div className="my-1 border-t border-gray-100 px-2 py-1 text-xs font-medium text-gray-400">
                  Other Contractors
                </div>
              )}
            </>
          )}
          {otherContractors.map((c) => (
            <SelectItem key={c.id} value={c.id}>
              {c.name}
            </SelectItem>
          ))}
          {!hasContractors && (
            <div className="px-2 py-2 text-sm text-gray-500">
              No contractors available.
            </div>
          )}
        </SelectContent>
      </Select>
    </div>
  );
}
