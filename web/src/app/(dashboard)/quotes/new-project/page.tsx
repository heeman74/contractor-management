"use client";

import { useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import { apiPost, ApiError } from "@/lib/api-client";
import type { Quote } from "@/types/api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  ProjectQuoteFieldSection,
  ProjectQuoteItem,
  buildProjectQuotePayload,
  emptyFieldSection,
  emptyItem,
  quoteTotal,
  sectionTotal,
  validateProjectQuote,
} from "./_lib/project-quote";

export default function NewProjectQuotePage() {
  const router = useRouter();
  const queryClient = useQueryClient();
  const keySeq = useRef(0);
  const nextKey = () => `k${keySeq.current++}`;

  const [title, setTitle] = useState("");
  const [sections, setSections] = useState<ProjectQuoteFieldSection[]>(() => [
    emptyFieldSection("s0", "i0"),
  ]);

  const total = quoteTotal(sections);

  const createMutation = useMutation({
    mutationFn: () => apiPost<Quote>("/api/v1/quotes/", buildProjectQuotePayload(title, sections)),
    onSuccess: (quote) => {
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Project quote saved as draft.");
      router.push(`/quotes/${quote.id}`);
    },
    onError: (err: Error) =>
      toast.error(err instanceof ApiError ? err.detail : "Failed to save quote.", {
        duration: Infinity,
      }),
  });

  // --- section / item mutations (immutable updates) ---
  const patchSection = (key: string, patch: Partial<ProjectQuoteFieldSection>) =>
    setSections((prev) => prev.map((s) => (s.key === key ? { ...s, ...patch } : s)));

  const patchItem = (sectionKey: string, itemKey: string, patch: Partial<ProjectQuoteItem>) =>
    setSections((prev) =>
      prev.map((s) =>
        s.key === sectionKey
          ? { ...s, items: s.items.map((i) => (i.key === itemKey ? { ...i, ...patch } : i)) }
          : s
      )
    );

  const addSection = () =>
    setSections((prev) => [...prev, emptyFieldSection(nextKey(), nextKey())]);
  const removeSection = (key: string) =>
    setSections((prev) => prev.filter((s) => s.key !== key));
  const addItem = (sectionKey: string) =>
    setSections((prev) =>
      prev.map((s) =>
        s.key === sectionKey ? { ...s, items: [...s.items, emptyItem(nextKey())] } : s
      )
    );
  const removeItem = (sectionKey: string, itemKey: string) =>
    setSections((prev) =>
      prev.map((s) =>
        s.key === sectionKey
          ? { ...s, items: s.items.filter((i) => i.key !== itemKey) }
          : s
      )
    );

  const handleSave = () => {
    const check = validateProjectQuote(title, sections);
    if (!check.ok) {
      toast.error(check.error);
      return;
    }
    createMutation.mutate();
  };

  return (
    <div className="mx-auto max-w-4xl space-y-6 pb-24">
      <div className="space-y-1">
        <h1 className="text-xl font-semibold text-gray-900">New Project Quote</h1>
        <p className="text-sm text-gray-500">
          Group the work into fields (trades). When the client approves this quote it
          becomes a project with one job per field.
        </p>
      </div>

      <div className="max-w-md">
        <Label htmlFor="pq-title">Project title</Label>
        <Input
          id="pq-title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="e.g. Downtown Cafe Buildout"
          className="mt-1"
        />
      </div>

      {sections.map((section, sIdx) => (
        <Card key={section.key} data-testid="field-section">
          <CardHeader className="flex flex-row items-center justify-between gap-3 space-y-0">
            <div className="flex-1">
              <Label htmlFor={`field-${section.key}`}>Field / trade</Label>
              <Input
                id={`field-${section.key}`}
                value={section.field}
                onChange={(e) => patchSection(section.key, { field: e.target.value })}
                placeholder="e.g. Electrical"
                className="mt-1 max-w-xs"
              />
            </div>
            <div className="flex items-center gap-3 self-end">
              <span className="text-sm text-gray-500">
                ${sectionTotal(section).toFixed(2)}
              </span>
              {sections.length > 1 && (
                <button
                  type="button"
                  onClick={() => removeSection(section.key)}
                  aria-label={`Remove field ${section.field || sIdx + 1}`}
                  className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-destructive"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              )}
            </div>
          </CardHeader>
          <CardContent className="space-y-2">
            {section.items.map((item) => (
              <div key={item.key} className="flex items-end gap-2">
                <div className="w-[110px]">
                  <Select
                    value={item.item_type}
                    onValueChange={(v) => {
                      if (v) patchItem(section.key, item.key, { item_type: v as "labor" | "material" });
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
                  onChange={(e) => patchItem(section.key, item.key, { description: e.target.value })}
                  placeholder="Description"
                  className="flex-1"
                />
                <Input
                  aria-label="Quantity"
                  type="number"
                  min="0"
                  step="0.5"
                  value={item.quantity}
                  onChange={(e) => patchItem(section.key, item.key, { quantity: e.target.value })}
                  className="w-[72px]"
                />
                <Input
                  aria-label="Unit"
                  value={item.unit}
                  onChange={(e) => patchItem(section.key, item.key, { unit: e.target.value })}
                  placeholder="unit"
                  className="w-[72px]"
                />
                <Input
                  aria-label="Unit price"
                  type="number"
                  min="0"
                  step="0.01"
                  value={item.unit_price}
                  onChange={(e) => patchItem(section.key, item.key, { unit_price: e.target.value })}
                  className="w-[96px]"
                />
                {section.items.length > 1 && (
                  <button
                    type="button"
                    onClick={() => removeItem(section.key, item.key)}
                    aria-label="Remove line item"
                    className="mb-1.5 rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-destructive"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </button>
                )}
              </div>
            ))}
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => addItem(section.key)}
            >
              <Plus className="h-3.5 w-3.5" />
              Add line item
            </Button>
          </CardContent>
        </Card>
      ))}

      <div className="flex items-center justify-between">
        <Button type="button" variant="outline" onClick={addSection} data-testid="add-field-button">
          <Plus className="h-4 w-4" />
          Add field
        </Button>
        <span className="text-sm font-medium text-gray-900">
          Total: ${total.toFixed(2)}
        </span>
      </div>

      <div className="flex items-center justify-end gap-3">
        <Button type="button" variant="ghost" onClick={() => router.push("/quotes")}>
          Cancel
        </Button>
        <Button type="button" onClick={handleSave} disabled={createMutation.isPending}>
          {createMutation.isPending ? "Saving…" : "Save Draft"}
        </Button>
      </div>
    </div>
  );
}
