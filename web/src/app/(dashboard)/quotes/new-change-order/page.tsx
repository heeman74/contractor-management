"use client";

import { formatCurrency } from "@/lib/format";
import { Suspense, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import { apiPost, ApiError } from "@/lib/api-client";
import type { Quote } from "@/types/api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  ChangeOrderForm,
  ChangeOrderItem,
  ChangeOrderTarget,
  buildChangeOrderPayload,
  changeOrderTotal,
  emptyChangeOrderForm,
  emptyChangeOrderItem,
  validateChangeOrder,
} from "./_lib/change-order";

export default function NewChangeOrderPage() {
  return (
    <Suspense fallback={<div className="p-6" />}>
      <NewChangeOrderContent />
    </Suspense>
  );
}

function NewChangeOrderContent() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const searchParams = useSearchParams();
  const projectId = searchParams.get("project_id") ?? "";
  const originatingJobId = searchParams.get("originating_job_id") ?? "";

  const keySeq = useRef(0);
  const nextKey = () => `k${keySeq.current++}`;

  const [form, setForm] = useState<ChangeOrderForm>(() => emptyChangeOrderForm("i0"));
  const total = changeOrderTotal(form.items);
  const missingContext = !projectId || !originatingJobId;

  const createMutation = useMutation({
    mutationFn: () =>
      apiPost<Quote>(
        "/api/v1/quotes/",
        buildChangeOrderPayload(projectId, originatingJobId, form)
      ),
    onSuccess: (quote) => {
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Change order saved as draft.");
      router.push(`/quotes/${quote.id}`);
    },
    onError: (err: Error) =>
      toast.error(err instanceof ApiError ? err.detail : "Failed to save change order.", {
        duration: Infinity,
      }),
  });

  const patchForm = (patch: Partial<ChangeOrderForm>) =>
    setForm((prev) => ({ ...prev, ...patch }));
  const patchItem = (key: string, patch: Partial<ChangeOrderItem>) =>
    setForm((prev) => ({
      ...prev,
      items: prev.items.map((item) => (item.key === key ? { ...item, ...patch } : item)),
    }));
  const addItem = () =>
    setForm((prev) => ({ ...prev, items: [...prev.items, emptyChangeOrderItem(nextKey())] }));
  const removeItem = (key: string) =>
    setForm((prev) => ({ ...prev, items: prev.items.filter((item) => item.key !== key) }));

  const handleSave = () => {
    if (missingContext) {
      toast.error("Missing project or originating job.");
      return;
    }
    const check = validateChangeOrder(form);
    if (!check.ok) {
      toast.error(check.error);
      return;
    }
    createMutation.mutate();
  };

  return (
    <div className="mx-auto max-w-3xl space-y-6 pb-24">
      <div className="space-y-1">
        <h1 className="text-xl font-semibold text-gray-900">New Change Order</h1>
        <p className="text-sm text-gray-500">
          Price the added or corrective work. When the client approves it, the work is
          added to this project.
        </p>
      </div>

      {missingContext && (
        <div className="rounded-lg bg-destructive/10 px-4 py-3 text-sm text-destructive">
          This page must be opened from a job that belongs to a project.
        </div>
      )}

      <div>
        <Label htmlFor="co-reason">Reason for change</Label>
        <Textarea
          id="co-reason"
          value={form.reason}
          onChange={(e) => patchForm({ reason: e.target.value })}
          rows={3}
          placeholder="e.g. Rotted subfloor discovered under the existing tile"
          className="mt-1"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label>Apply approved work to</Label>
          <Select
            value={form.co_target}
            onValueChange={(v) => {
              if (v) patchForm({ co_target: v as ChangeOrderTarget });
            }}
          >
            <SelectTrigger className="mt-1">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="new_job">A new job in the project</SelectItem>
              <SelectItem value="existing_job">This job (extend it)</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div>
          <Label htmlFor="co-days">Schedule impact (days)</Label>
          <Input
            id="co-days"
            type="number"
            min="0"
            value={form.schedule_impact_days}
            onChange={(e) => patchForm({ schedule_impact_days: e.target.value })}
            placeholder="0"
            className="mt-1"
          />
        </div>
      </div>

      <Card>
        <CardContent className="space-y-2 pt-6">
          <Label>Line items</Label>
          {form.items.map((item) => (
            <div key={item.key} className="flex items-end gap-2">
              <div className="w-[110px]">
                <Select
                  value={item.item_type}
                  onValueChange={(v) => {
                    if (v) patchItem(item.key, { item_type: v as "labor" | "material" });
                  }}
                >
                  <SelectTrigger aria-label="Item type">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="labor">Labor</SelectItem>
                    <SelectItem value="material">Material</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <Input
                aria-label="Description"
                value={item.description}
                onChange={(e) => patchItem(item.key, { description: e.target.value })}
                placeholder="Description"
                className="flex-1"
              />
              <Input
                aria-label="Quantity"
                type="number"
                min="0"
                step="0.5"
                value={item.quantity}
                onChange={(e) => patchItem(item.key, { quantity: e.target.value })}
                className="w-[72px]"
              />
              <Input
                aria-label="Unit"
                value={item.unit}
                onChange={(e) => patchItem(item.key, { unit: e.target.value })}
                placeholder="unit"
                className="w-[72px]"
              />
              <Input
                aria-label="Unit price"
                type="number"
                min="0"
                step="0.01"
                value={item.unit_price}
                onChange={(e) => patchItem(item.key, { unit_price: e.target.value })}
                className="w-[96px]"
              />
              {form.items.length > 1 && (
                <button
                  type="button"
                  onClick={() => removeItem(item.key)}
                  aria-label="Remove line item"
                  className="mb-1.5 rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-destructive"
                >
                  <Trash2 className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          ))}
          <Button type="button" variant="outline" size="sm" onClick={addItem}>
            <Plus className="h-3.5 w-3.5" />
            Add line item
          </Button>
        </CardContent>
      </Card>

      <div className="flex items-center justify-end gap-3">
        <span className="mr-auto text-sm font-medium text-gray-900">
          Total: {formatCurrency(total)}
        </span>
        <Button type="button" variant="ghost" onClick={() => router.back()}>
          Cancel
        </Button>
        <Button
          type="button"
          onClick={handleSave}
          disabled={createMutation.isPending || missingContext}
        >
          {createMutation.isPending ? "Saving…" : "Save Draft"}
        </Button>
      </div>
    </div>
  );
}
