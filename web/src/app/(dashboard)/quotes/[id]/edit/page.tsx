"use client";

import { use, useState } from "react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { LineItemsTable } from "./_components/line-items-table";
import { QuoteSettingsCard } from "./_components/quote-settings-card";
import { QuotePreview } from "./_components/quote-preview";
import { StickyTotalsBar } from "./_components/sticky-totals-bar";
import { useQuoteEditor } from "./_hooks/use-quote-editor";
import { useQuoteSuggestions } from "./_hooks/use-quote-suggestions";
import { computeQuoteTotals } from "./_lib/quote-form";

type EditorMode = "edit" | "preview";

const REGENERATE_TAIL =
  "Lines you've accepted or edited stay exactly as they are.";

function regenerateBodyCopy(count: number): string {
  return count === 1
    ? `1 unreviewed suggestion will be replaced with a fresh one. ${REGENERATE_TAIL}`
    : `${count} unreviewed suggestions will be replaced with fresh ones. ${REGENERATE_TAIL}`;
}

export default function QuoteEditPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const editor = useQuoteEditor(id);
  const suggestions = useQuoteSuggestions(id);
  const [mode, setMode] = useState<EditorMode>("edit");
  const [regenerateOpen, setRegenerateOpen] = useState(false);

  const { form } = editor;
  const totals = computeQuoteTotals(form.watch());

  const lineItems = form.watch("line_items");
  const aiLineCount = lineItems.filter((item) => item.ai_origin).length;
  const unreviewedCount = lineItems.filter(
    (item) => item.ai_origin && item.review_state === "unreviewed"
  ).length;

  function confirmRegenerate() {
    setRegenerateOpen(false);
    suggestions.suggest();
  }

  if (editor.quoteLoading && !editor.isNew) {
    return (
      <div className="space-y-4 animate-pulse">
        <div className="h-8 w-1/3 rounded bg-gray-200" />
        <div className="h-64 rounded-xl bg-gray-100" />
      </div>
    );
  }

  return (
    <div className="space-y-6 pb-24">
      {/* Page header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-xl font-semibold text-gray-900">
          {editor.pageTitle}
        </h1>
        <div className="flex items-center gap-3 flex-wrap">
          {editor.templates.length > 0 && (
            <Select<string>
              onValueChange={(v) => {
                if (v) editor.selectTemplate(v);
              }}
            >
              <SelectTrigger className="w-[200px] text-sm">
                <SelectValue placeholder="Load from template..." />
              </SelectTrigger>
              <SelectContent>
                {editor.templates.map((t) => (
                  <SelectItem key={t.id} value={t.id}>
                    {t.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}

          <Tabs value={mode} onValueChange={(v) => setMode(v as EditorMode)}>
            <TabsList>
              <TabsTrigger value="edit">Edit</TabsTrigger>
              <TabsTrigger value="preview">Preview</TabsTrigger>
            </TabsList>
          </Tabs>
        </div>
      </div>

      {/* Form */}
      <form onSubmit={form.handleSubmit(editor.submit)}>
        {mode === "edit" ? (
          <div className="space-y-6">
            <LineItemsTable
              form={form}
              quote={editor.existingQuote ?? null}
              isNewQuote={editor.isNew}
              aiLineCount={aiLineCount}
              unreviewedCount={unreviewedCount}
              suggestion={suggestions}
              onRegenerateNeeded={() => setRegenerateOpen(true)}
            />
            <QuoteSettingsCard form={form} />
          </div>
        ) : (
          <QuotePreview
            values={form.getValues()}
            revisionNumber={editor.revisionNumber}
          />
        )}

        <div className="mt-6 flex items-center justify-end gap-3">
          <Button
            type="button"
            variant="ghost"
            onClick={editor.cancel}
            disabled={editor.isMutating || form.formState.isSubmitting}
          >
            Discard Changes
          </Button>
          <Button
            type="submit"
            disabled={editor.isMutating || form.formState.isSubmitting}
          >
            {editor.isMutating ? "Saving..." : "Save Draft"}
          </Button>
        </div>
      </form>

      {/* Template replace confirmation dialog */}
      <Dialog
        open={editor.pendingTemplate !== null}
        onOpenChange={(open) => {
          if (!open) editor.cancelPendingTemplate();
        }}
      >
        <DialogContent showCloseButton>
          <DialogHeader>
            <DialogTitle>Replace current line items with template?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-gray-600">
            This will replace your existing line items with the template
            &ldquo;{editor.pendingTemplate?.name}&rdquo;. This action cannot be
            undone.
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={editor.cancelPendingTemplate}>
              Cancel
            </Button>
            <Button onClick={editor.confirmPendingTemplate}>
              Replace Line Items
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Regenerate confirmation — appears only when there is unreviewed
          work to replace; with none, "Suggest again" runs the mutation
          immediately (nothing destructive is happening). */}
      <Dialog
        open={regenerateOpen}
        onOpenChange={(open) => {
          if (!open) setRegenerateOpen(false);
        }}
      >
        <DialogContent showCloseButton>
          <DialogHeader>
            <DialogTitle>Replace unreviewed suggestions?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-gray-600">
            {regenerateBodyCopy(unreviewedCount)}
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRegenerateOpen(false)}>
              Cancel
            </Button>
            <Button variant="default" onClick={confirmRegenerate}>
              Replace Suggestions
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <StickyTotalsBar {...totals} />
    </div>
  );
}
