"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet, apiPost, ApiError } from "@/lib/api-client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type {
  Job,
  JobCreateRequest,
  ClientListItem,
  ContractorListItem,
} from "@/types/api";
import type { ProjectResponse } from "@/types/projects";
import { isManager } from "@/lib/roles";

const TRADE_TYPES = [
  "Plumbing",
  "Electrical",
  "Building",
  "Painting",
  "Carpentry",
  "Landscaping",
  "HVAC",
  "General",
];

const PRIORITIES = ["low", "medium", "high", "urgent"];

interface CreateJobDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateJobDialog({ open, onOpenChange }: CreateJobDialogProps) {
  const queryClient = useQueryClient();

  // Form state
  const [description, setDescription] = useState("");
  const [tradeType, setTradeType] = useState("");
  const [priority, setPriority] = useState("medium");
  const [clientId, setClientId] = useState("");
  const [contractorId, setContractorId] = useState("");
  const [projectId, setProjectId] = useState("");
  const [managerId, setManagerId] = useState("");
  const [estimatedDuration, setEstimatedDuration] = useState("");
  const [notes, setNotes] = useState("");
  const [formError, setFormError] = useState("");

  // Fetch clients for dropdown
  const { data: clients } = useQuery({
    queryKey: ["clients-list"],
    queryFn: () => apiGet<ClientListItem[]>("/api/v1/crm/clients?limit=100"),
    enabled: open,
  });

  // Fetch all users and filter to contractors client-side
  // (backend list endpoint doesn't support role query param)
  const { data: contractors } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<ContractorListItem[]>("/api/v1/users/"),
    enabled: open,
    select: (users) => users.filter((u) => u.roles.includes("contractor")),
  });

  // Fetch projects for the optional project link
  const { data: projects } = useQuery({
    queryKey: ["projects"],
    queryFn: () => apiGet<ProjectResponse[]>("/api/v1/projects/"),
    enabled: open,
  });

  // Manager candidates: users holding a manager-capable role (owner/admin/PM)
  const { data: managers } = useQuery({
    queryKey: ["users"],
    queryFn: () => apiGet<ContractorListItem[]>("/api/v1/users/"),
    enabled: open,
    select: (users) => users.filter((u) => isManager(u.roles)),
  });

  const resetForm = () => {
    setDescription("");
    setTradeType("");
    setPriority("medium");
    setClientId("");
    setContractorId("");
    setProjectId("");
    setManagerId("");
    setEstimatedDuration("");
    setNotes("");
    setFormError("");
  };

  const createJobMutation = useMutation<Job, Error, JobCreateRequest>({
    mutationFn: (payload) => apiPost<Job>("/api/v1/jobs/", payload),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["jobs"] });
      toast.success("Job created successfully");
      resetForm();
      onOpenChange(false);
    },
    onError: (error) => {
      if (error instanceof ApiError) {
        setFormError(error.detail);
      } else {
        setFormError("An unexpected error occurred");
      }
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    setFormError("");

    if (!description.trim()) {
      setFormError("Description is required");
      return;
    }
    if (!tradeType) {
      setFormError("Trade type is required");
      return;
    }

    const payload: JobCreateRequest = {
      description: description.trim(),
      trade_type: tradeType,
      priority,
    };

    if (clientId) payload.client_id = clientId;
    if (contractorId) payload.contractor_id = contractorId;
    if (projectId) payload.project_id = projectId;
    if (managerId) payload.manager_id = managerId;
    if (estimatedDuration) {
      const mins = parseInt(estimatedDuration, 10);
      if (!isNaN(mins) && mins > 0) payload.estimated_duration_minutes = mins;
    }
    if (notes.trim()) payload.notes = notes.trim();

    createJobMutation.mutate(payload);
  };

  const handleOpenChange = (nextOpen: boolean) => {
    if (!nextOpen) resetForm();
    onOpenChange(nextOpen);
  };

  // base-ui SelectValue renders the raw value (a UUID) by default — map ids
  // back to display names so the closed trigger shows the person/project name.
  const userLabel = (users: ContractorListItem[] | ClientListItem[] | undefined) =>
    function renderUser(value: string | null) {
      if (!value) return null;
      const u = (users as Array<ContractorListItem | ClientListItem> | undefined)?.find(
        (x) => x.id === value
      );
      if (!u) return value.slice(0, 8);
      return [u.first_name, u.last_name].filter(Boolean).join(" ") || u.email;
    };
  const projectLabel = (value: string | null) =>
    value ? (projects?.find((p) => p.id === value)?.name ?? value.slice(0, 8)) : null;

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Create New Job</DialogTitle>
          <DialogDescription>
            Fill in the details below to create a new job.
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Description */}
          <div className="space-y-1.5">
            <Label htmlFor="job-description">Description *</Label>
            <Textarea
              id="job-description"
              placeholder="Describe the job..."
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="resize-none"
              data-testid="job-description"
            />
          </div>

          {/* Trade Type */}
          <div className="space-y-1.5">
            <Label>Trade Type *</Label>
            <Select<string>
              value={tradeType}
              onValueChange={(v) => setTradeType(v ?? "")}
            >
              <SelectTrigger
                className="w-full"
                data-testid="trade-type-trigger"
              >
                <SelectValue placeholder="Select trade type" />
              </SelectTrigger>
              <SelectContent>
                {TRADE_TYPES.map((trade) => (
                  <SelectItem key={trade} value={trade}>
                    {trade}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Priority */}
          <div className="space-y-1.5">
            <Label>Priority</Label>
            <Select<string>
              value={priority}
              onValueChange={(v) => setPriority(v ?? "")}
            >
              <SelectTrigger
                className="w-full"
                data-testid="priority-trigger"
              >
                <SelectValue placeholder="Select priority" />
              </SelectTrigger>
              <SelectContent>
                {PRIORITIES.map((p) => (
                  <SelectItem key={p} value={p}>
                    {p.charAt(0).toUpperCase() + p.slice(1)}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Client */}
          <div className="space-y-1.5">
            <Label>Client (optional)</Label>
            <Select<string>
              value={clientId}
              onValueChange={(v) => setClientId(v ?? "")}
            >
              <SelectTrigger
                className="w-full"
                data-testid="client-trigger"
              >
                <SelectValue placeholder="Select client">
                  {userLabel(clients)}
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                {clients?.map((client) => (
                  <SelectItem key={client.id} value={client.id}>
                    {[client.first_name, client.last_name]
                      .filter(Boolean)
                      .join(" ") || client.email}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Contractor */}
          <div className="space-y-1.5">
            <Label>Contractor (optional)</Label>
            <Select<string>
              value={contractorId}
              onValueChange={(v) => setContractorId(v ?? "")}
            >
              <SelectTrigger
                className="w-full"
                data-testid="contractor-trigger"
              >
                <SelectValue placeholder="Select contractor">
                  {userLabel(contractors)}
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                {contractors?.map((contractor) => (
                  <SelectItem key={contractor.id} value={contractor.id}>
                    {[contractor.first_name, contractor.last_name]
                      .filter(Boolean)
                      .join(" ") || contractor.email}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Manager */}
          <div className="space-y-1.5">
            <Label>Project Manager (optional)</Label>
            <Select<string>
              value={managerId}
              onValueChange={(v) => setManagerId(v ?? "")}
            >
              <SelectTrigger
                className="w-full"
                data-testid="manager-trigger"
              >
                <SelectValue placeholder="Select manager">
                  {userLabel(managers)}
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                {managers?.map((manager) => (
                  <SelectItem key={manager.id} value={manager.id}>
                    {[manager.first_name, manager.last_name]
                      .filter(Boolean)
                      .join(" ") || manager.email}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Project */}
          <div className="space-y-1.5">
            <Label>Project (optional)</Label>
            <Select<string>
              value={projectId}
              onValueChange={(v) => setProjectId(v ?? "")}
            >
              <SelectTrigger
                className="w-full"
                data-testid="project-trigger"
              >
                <SelectValue placeholder="Link to a project">
                  {projectLabel}
                </SelectValue>
              </SelectTrigger>
              <SelectContent>
                {projects?.map((project) => (
                  <SelectItem key={project.id} value={project.id}>
                    {project.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* Estimated Duration */}
          <div className="space-y-1.5">
            <Label htmlFor="estimated-duration">
              Estimated Duration (minutes)
            </Label>
            <Input
              id="estimated-duration"
              type="number"
              min="1"
              placeholder="e.g. 120"
              value={estimatedDuration}
              onChange={(e) => setEstimatedDuration(e.target.value)}
              data-testid="estimated-duration"
            />
          </div>

          {/* Notes */}
          <div className="space-y-1.5">
            <Label htmlFor="job-notes">Notes (optional)</Label>
            <Textarea
              id="job-notes"
              placeholder="Additional notes..."
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="resize-none"
              data-testid="job-notes"
            />
          </div>

          {/* Error message */}
          {formError && (
            <p className="text-sm text-destructive" data-testid="form-error">
              {formError}
            </p>
          )}

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => handleOpenChange(false)}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={createJobMutation.isPending}>
              {createJobMutation.isPending ? "Creating..." : "Create Job"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
