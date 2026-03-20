"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { CalendarIcon } from "lucide-react";
import { format } from "date-fns";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Calendar } from "@/components/ui/calendar";
import { cn } from "@/lib/utils";
import { createProject } from "@/lib/api/projects";
import type { ProjectResponse, ProjectCreate } from "@/types/projects";

interface CreateProjectDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateProjectDialog({
  open,
  onOpenChange,
}: CreateProjectDialogProps) {
  const queryClient = useQueryClient();

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [address, setAddress] = useState("");
  const [startDate, setStartDate] = useState<Date | undefined>(undefined);
  const [endDate, setEndDate] = useState<Date | undefined>(undefined);
  const [nameError, setNameError] = useState("");
  const [dateError, setDateError] = useState("");

  const resetForm = () => {
    setName("");
    setDescription("");
    setAddress("");
    setStartDate(undefined);
    setEndDate(undefined);
    setNameError("");
    setDateError("");
  };

  const createMutation = useMutation<ProjectResponse, Error, ProjectCreate>({
    mutationFn: createProject,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      toast.success("Project created.");
      resetForm();
      onOpenChange(false);
    },
    onError: () => {
      toast.error("Something went wrong. Please try again.");
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setNameError("");
    setDateError("");

    let valid = true;

    if (!name.trim()) {
      setNameError("Project name is required.");
      valid = false;
    }

    if (startDate && endDate && endDate <= startDate) {
      setDateError("End date must be after start date.");
      valid = false;
    }

    if (!valid) return;

    const payload: ProjectCreate = {
      name: name.trim(),
    };
    if (description.trim()) payload.description = description.trim();
    if (address.trim()) payload.address = address.trim();
    if (startDate) payload.target_start_date = format(startDate, "yyyy-MM-dd");
    if (endDate) payload.target_end_date = format(endDate, "yyyy-MM-dd");

    createMutation.mutate(payload);
  };

  const handleOpenChange = (next: boolean) => {
    if (!next) resetForm();
    onOpenChange(next);
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Create Project</DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Project Name */}
          <div className="space-y-1.5">
            <Label htmlFor="project-name">Project Name *</Label>
            <Input
              id="project-name"
              placeholder="e.g., Kitchen Renovation"
              value={name}
              onChange={(e) => setName(e.target.value)}
              data-testid="project-name-input"
            />
            {nameError && (
              <p className="text-sm text-destructive" data-testid="name-error">
                {nameError}
              </p>
            )}
          </div>

          {/* Description */}
          <div className="space-y-1.5">
            <Label htmlFor="project-description">Description</Label>
            <Textarea
              id="project-description"
              placeholder="Project details..."
              rows={3}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="resize-none"
              data-testid="project-description-input"
            />
          </div>

          {/* Address */}
          <div className="space-y-1.5">
            <Label htmlFor="project-address">Address</Label>
            <Input
              id="project-address"
              placeholder="123 Main St"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              data-testid="project-address-input"
            />
          </div>

          {/* Target Start Date */}
          <div className="space-y-1.5">
            <Label>Target Start Date</Label>
            <Popover>
              <PopoverTrigger
                className={cn(
                  "flex h-9 w-full items-center justify-start gap-2 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background",
                  !startDate && "text-muted-foreground"
                )}
                aria-label="Select start date"
                data-testid="start-date-trigger"
              >
                <CalendarIcon className="h-4 w-4" />
                {startDate ? format(startDate, "MMM d, yyyy") : "Pick a date"}
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0" align="start">
                <Calendar
                  mode="single"
                  selected={startDate}
                  onSelect={setStartDate}
                />
              </PopoverContent>
            </Popover>
          </div>

          {/* Target End Date */}
          <div className="space-y-1.5">
            <Label>Target End Date</Label>
            <Popover>
              <PopoverTrigger
                className={cn(
                  "flex h-9 w-full items-center justify-start gap-2 rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background",
                  !endDate && "text-muted-foreground"
                )}
                aria-label="Select end date"
                data-testid="end-date-trigger"
              >
                <CalendarIcon className="h-4 w-4" />
                {endDate ? format(endDate, "MMM d, yyyy") : "Pick a date"}
              </PopoverTrigger>
              <PopoverContent className="w-auto p-0" align="start">
                <Calendar
                  mode="single"
                  selected={endDate}
                  onSelect={setEndDate}
                />
              </PopoverContent>
            </Popover>
            {dateError && (
              <p className="text-sm text-destructive" data-testid="date-error">
                {dateError}
              </p>
            )}
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => handleOpenChange(false)}
            >
              Cancel
            </Button>
            <Button
              type="submit"
              disabled={createMutation.isPending}
              data-testid="create-project-submit"
            >
              {createMutation.isPending ? "Creating..." : "Create Project"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
