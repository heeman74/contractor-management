"use client";

import { useState, useCallback, type FormEvent } from "react";
import { useCreateStatusUpdate } from "@/lib/hooks/useForeman";
import { toast } from "sonner";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";

interface StatusUpdateFormProps {
  projectId: string;
  onSuccess?: () => void;
}

export function StatusUpdateForm({ projectId, onSuccess }: StatusUpdateFormProps) {
  const [statusText, setStatusText] = useState("");
  const [weatherConditions, setWeatherConditions] = useState("");
  const [workersOnSite, setWorkersOnSite] = useState("");
  const [safetyIncidents, setSafetyIncidents] = useState("0");
  const [blockers, setBlockers] = useState("");

  const createMutation = useCreateStatusUpdate();

  const handleSubmit = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();

      if (!statusText.trim()) {
        toast.error("Status text is required");
        return;
      }

      try {
        await createMutation.mutateAsync({
          project_id: projectId,
          status_text: statusText.trim(),
          weather_conditions: weatherConditions.trim() || null,
          workers_on_site: workersOnSite ? parseInt(workersOnSite, 10) : null,
          safety_incidents: parseInt(safetyIncidents, 10) || 0,
          blockers: blockers.trim() || null,
        });

        toast.success("Status update submitted");
        setStatusText("");
        setWeatherConditions("");
        setWorkersOnSite("");
        setSafetyIncidents("0");
        setBlockers("");
        onSuccess?.();
      } catch (err) {
        const message = err instanceof Error ? err.message : "Failed to submit status update";
        toast.error(message);
      }
    },
    [
      projectId,
      statusText,
      weatherConditions,
      workersOnSite,
      safetyIncidents,
      blockers,
      createMutation,
      onSuccess,
    ]
  );

  return (
    <form
      onSubmit={handleSubmit}
      className="rounded-xl border border-gray-200 bg-white p-5 shadow-sm space-y-4"
    >
      <h3 className="text-base font-medium text-gray-900">
        Submit Daily Status Update
      </h3>

      {/* Status text (required) */}
      <div className="space-y-1.5">
        <Label htmlFor="status-text">
          Status Update <span className="text-red-500">*</span>
        </Label>
        <Textarea
          id="status-text"
          value={statusText}
          onChange={(e) => setStatusText(e.target.value)}
          placeholder="Describe today's progress, work completed, and any notes..."
          rows={4}
          required
        />
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {/* Weather conditions */}
        <div className="space-y-1.5">
          <Label htmlFor="weather">Weather Conditions</Label>
          <Input
            id="weather"
            value={weatherConditions}
            onChange={(e) => setWeatherConditions(e.target.value)}
            placeholder="e.g., Sunny, 72F"
          />
        </div>

        {/* Workers on site */}
        <div className="space-y-1.5">
          <Label htmlFor="workers">Workers on Site</Label>
          <Input
            id="workers"
            type="number"
            min="0"
            value={workersOnSite}
            onChange={(e) => setWorkersOnSite(e.target.value)}
            placeholder="0"
          />
        </div>

        {/* Safety incidents */}
        <div className="space-y-1.5">
          <Label htmlFor="incidents">Safety Incidents</Label>
          <Input
            id="incidents"
            type="number"
            min="0"
            value={safetyIncidents}
            onChange={(e) => setSafetyIncidents(e.target.value)}
          />
        </div>
      </div>

      {/* Blockers */}
      <div className="space-y-1.5">
        <Label htmlFor="blockers">Blockers</Label>
        <Textarea
          id="blockers"
          value={blockers}
          onChange={(e) => setBlockers(e.target.value)}
          placeholder="Describe any blockers or issues preventing progress..."
          rows={2}
        />
      </div>

      {/* Submit */}
      <div className="flex justify-end">
        <Button type="submit" disabled={createMutation.isPending}>
          {createMutation.isPending && (
            <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
          )}
          Submit Update
        </Button>
      </div>
    </form>
  );
}
