"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { Button } from "@/components/ui/button";
import { formatCurrency } from "@/lib/format";
import { ChangeOrderContextFields } from "./_components/change-order-context-fields";
import { ChangeOrderLineItems } from "./_components/change-order-line-items";
import { useChangeOrderBuilder } from "./_hooks/use-change-order-builder";

const PAGE_TITLE = "New Change Order";
const PAGE_SUBTITLE =
  "Price the added or corrective work. When the client approves it, the work is added to this project.";
const MISSING_CONTEXT_NOTICE =
  "This page must be opened from a job that belongs to a project.";

export default function NewChangeOrderPage() {
  return (
    <Suspense fallback={<div className="p-6" />}>
      <NewChangeOrderContent />
    </Suspense>
  );
}

function NewChangeOrderContent() {
  const searchParams = useSearchParams();
  const builder = useChangeOrderBuilder(
    searchParams.get("project_id") ?? "",
    searchParams.get("originating_job_id") ?? ""
  );

  return (
    <div className="mx-auto max-w-3xl space-y-6 pb-24">
      <div className="space-y-1">
        <h1 className="text-xl font-semibold text-gray-900">{PAGE_TITLE}</h1>
        <p className="text-sm text-gray-500">{PAGE_SUBTITLE}</p>
      </div>

      {builder.missingContext && (
        <div className="rounded-lg bg-destructive/10 px-4 py-3 text-sm text-destructive">
          {MISSING_CONTEXT_NOTICE}
        </div>
      )}

      <ChangeOrderContextFields form={builder.form} onPatch={builder.patchForm} />

      <ChangeOrderLineItems
        items={builder.form.items}
        onPatchItem={builder.patchItem}
        onAddItem={builder.addItem}
        onRemoveItem={builder.removeItem}
      />

      <div className="flex items-center justify-end gap-3">
        <span className="mr-auto text-sm font-medium text-gray-900">
          Total: {formatCurrency(builder.total)}
        </span>
        <Button type="button" variant="ghost" onClick={builder.cancel}>
          Cancel
        </Button>
        <Button
          type="button"
          onClick={builder.save}
          disabled={builder.isSaving || builder.missingContext}
        >
          {builder.isSaving ? "Saving…" : "Save Draft"}
        </Button>
      </div>
    </div>
  );
}
