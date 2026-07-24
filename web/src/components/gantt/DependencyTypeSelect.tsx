"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export type DependencyType = "FS" | "SS" | "FF" | "SE";

const DEPENDENCY_TYPE_LABELS: Record<DependencyType, string> = {
  FS: "FS — Finish to Start",
  SS: "SS — Start to Start",
  FF: "FF — Finish to Finish",
  SE: "SE — Start to End",
};

interface DependencyTypeSelectProps {
  onConfirm: (type: DependencyType, lagDays: number) => void;
  onCancel: () => void;
}

export function DependencyTypeSelect({
  onConfirm,
  onCancel,
}: DependencyTypeSelectProps) {
  const [depType, setDepType] = useState<DependencyType>("FS");
  const [lagDays, setLagDays] = useState<number>(0);
  const [lagInput, setLagInput] = useState("0");

  const handleLagChange = (value: string) => {
    setLagInput(value);
    const parsed = parseInt(value, 10);
    if (!isNaN(parsed)) {
      setLagDays(parsed);
    }
  };

  const handleConfirm = () => {
    onConfirm(depType, lagDays);
  };

  return (
    <div className="flex flex-col gap-3 p-3 min-w-[220px]">
      <div className="flex flex-col gap-1">
        <Label htmlFor="dep-type-select" className="text-xs font-medium text-gray-700">
          Dependency Type
        </Label>
        <Select
          value={depType}
          onValueChange={(val) => setDepType(val as DependencyType)}
        >
          <SelectTrigger id="dep-type-select" className="w-full">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {(Object.keys(DEPENDENCY_TYPE_LABELS) as DependencyType[]).map(
              (type) => (
                <SelectItem key={type} value={type}>
                  {DEPENDENCY_TYPE_LABELS[type]}
                </SelectItem>
              )
            )}
          </SelectContent>
        </Select>
      </div>

      <div className="flex flex-col gap-1">
        <Label htmlFor="lag-days-input" className="text-xs font-medium text-gray-700">
          Lag / Lead (days)
        </Label>
        <Input
          id="lag-days-input"
          type="number"
          value={lagInput}
          onChange={(e) => handleLagChange(e.target.value)}
          className="w-full"
        />
        <p className="text-xs text-gray-500">Positive = delay, negative = overlap</p>
      </div>

      <div className="flex gap-2 justify-end">
        <Button variant="outline" size="sm" onClick={onCancel}>
          Cancel
        </Button>
        <Button
          size="sm"
          className="bg-primary hover:bg-primary/90 text-white"
          onClick={handleConfirm}
        >
          Create Dependency
        </Button>
      </div>
    </div>
  );
}
