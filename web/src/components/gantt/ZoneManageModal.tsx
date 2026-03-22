"use client";

import { useState } from "react";
import { Trash2 } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import type { ProjectZoneResponse } from "@/types/dependencies";

interface ZoneManageModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  zones: ProjectZoneResponse[];
  onAddZone: (name: string) => Promise<void>;
  onDeleteZone: (id: string) => Promise<void>;
}

export function ZoneManageModal({
  open,
  onOpenChange,
  zones,
  onAddZone,
  onDeleteZone,
}: ZoneManageModalProps) {
  const [newZoneName, setNewZoneName] = useState("");
  const [duplicateError, setDuplicateError] = useState(false);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const [isAdding, setIsAdding] = useState(false);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  const handleAddZone = async () => {
    const trimmed = newZoneName.trim();
    if (!trimmed) return;

    const exists = zones.some(
      (z) => z.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (exists) {
      setDuplicateError(true);
      return;
    }

    setDuplicateError(false);
    setIsAdding(true);
    try {
      await onAddZone(trimmed);
      setNewZoneName("");
    } finally {
      setIsAdding(false);
    }
  };

  const handleDeleteZone = async (id: string) => {
    setDeletingId(id);
    try {
      await onDeleteZone(id);
      setConfirmDeleteId(null);
    } finally {
      setDeletingId(null);
    }
  };

  const handleNameChange = (value: string) => {
    setNewZoneName(value);
    if (duplicateError) setDuplicateError(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Project Zones</DialogTitle>
        </DialogHeader>

        {/* Zone list */}
        <div className="max-h-64 overflow-y-auto">
          {zones.length === 0 ? (
            <p className="text-sm text-gray-500 py-2 text-center">No zones yet.</p>
          ) : (
            <ul className="space-y-1">
              {zones.map((zone) => (
                <li key={zone.id} className="flex items-center justify-between py-1.5 px-1">
                  <span className="text-sm text-gray-800">{zone.name}</span>

                  {confirmDeleteId === zone.id ? (
                    <div className="flex items-center gap-1.5">
                      <span className="text-xs text-gray-600">Delete {zone.name}?</span>
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-6 px-2 text-xs text-red-600 border-red-300 hover:bg-red-50"
                        onClick={() => handleDeleteZone(zone.id)}
                        disabled={deletingId === zone.id}
                      >
                        Delete Zone
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-6 px-2 text-xs"
                        onClick={() => setConfirmDeleteId(null)}
                      >
                        Keep Zone
                      </Button>
                    </div>
                  ) : (
                    <button
                      className="p-1 rounded text-gray-400 hover:text-red-600 hover:bg-red-50 transition-colors"
                      onClick={() => setConfirmDeleteId(zone.id)}
                      aria-label={`Delete ${zone.name}`}
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  )}
                </li>
              ))}
            </ul>
          )}
        </div>

        <DialogFooter className="flex-col sm:flex-col gap-2">
          <div className="flex gap-2 w-full">
            <div className="flex-1">
              <Input
                placeholder="Zone name"
                value={newZoneName}
                onChange={(e) => handleNameChange(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") handleAddZone();
                }}
                aria-invalid={duplicateError}
              />
              {duplicateError && (
                <p className="text-xs text-red-600 mt-1">
                  A zone with this name already exists
                </p>
              )}
            </div>
            <Button
              className="bg-indigo-600 hover:bg-indigo-700 text-white flex-shrink-0"
              onClick={handleAddZone}
              disabled={isAdding || !newZoneName.trim()}
            >
              Add Zone
            </Button>
          </div>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
