import { Fragment, useId } from "react";
import {
  DndContext,
  closestCenter,
  type DragEndEvent,
  PointerSensor,
  useSensor,
  useSensors,
} from "@dnd-kit/core";
import {
  SortableContext,
  verticalListSortingStrategy,
} from "@dnd-kit/sortable";
import { Bot, Plus } from "lucide-react";
import {
  useFieldArray,
  type UseFormReturn,
} from "react-hook-form";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { FINANCE_VIEW_PERMISSION } from "@/features/finance/types";
import type { Quote } from "@/types/api";
import { AI_DISCLOSURE_NOTE } from "../../_lib/review-state";
import { AiLineSubRow } from "./ai-line-sub-row";
import { SuggestionNotice } from "./suggestion-notice";
import { UnreviewedBanner } from "./unreviewed-banner";
import { SortableLineItemRow } from "./sortable-line-item-row";
import { createEmptyLineItem, type QuoteFormValues } from "../_lib/quote-form";
import {
  PRICING_BASIS_CAPTION,
  UNBURDENED_LABOR_CAPTION,
  triggerDisabledReason,
  triggerLabel,
} from "../_lib/suggestion-copy";
import type { QuoteSuggestionResult } from "../_hooks/use-quote-suggestions";

const BASE_COLUMN_HEADERS: Array<{
  label: string;
  alignClass: string;
  width?: string;
}> = [
  { label: "Type", alignClass: "text-left", width: "w-[120px]" },
  { label: "Description", alignClass: "text-left" },
  { label: "Qty", alignClass: "text-right", width: "w-[72px]" },
  { label: "Unit", alignClass: "text-left", width: "w-[80px]" },
  { label: "Unit Price", alignClass: "text-right", width: "w-[112px]" },
];

const TRADE_COLUMN_HEADER = {
  label: "Trade",
  alignClass: "text-left",
  width: "w-[140px]",
};

const TOTAL_COLUMN_HEADER = {
  label: "Total",
  alignClass: "text-right",
  width: "w-[96px]",
};

interface QuoteSuggestionHandle {
  suggest: () => void;
  isPending: boolean;
  refusal: QuoteSuggestionResult | null;
}

interface LineItemsTableProps {
  form: UseFormReturn<QuoteFormValues>;
  quote: Quote | null;
  isNewQuote: boolean;
  aiLineCount: number;
  unreviewedCount: number;
  suggestion: QuoteSuggestionHandle;
  onRegenerateNeeded: () => void;
}

export function LineItemsTable({
  form,
  quote,
  isNewQuote,
  aiLineCount,
  unreviewedCount,
  suggestion,
  onRegenerateNeeded,
}: LineItemsTableProps) {
  const {
    control,
    register,
    watch,
    formState: { errors, isDirty },
  } = form;

  const { can } = usePermissions();
  const canViewFinance = can(FINANCE_VIEW_PERMISSION);

  const { fields, append, remove, move } = useFieldArray({
    control,
    name: "line_items",
  });

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } })
  );

  // Stable, SSR-safe id for DndContext. Without it, dnd-kit falls back to a
  // module-level counter for its accessibility ids (DndDescribedBy-N), which
  // drifts between the server and client render and causes a hydration mismatch.
  const dndContextId = useId();

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (active.id !== over?.id) {
      const oldIndex = fields.findIndex((f) => f.id === active.id);
      const newIndex = fields.findIndex((f) => f.id === over!.id);
      move(oldIndex, newIndex);
    }
  }

  function appendRow() {
    append(createEmptyLineItem(fields.length));
  }

  function handleAccept(index: number) {
    form.setValue(`line_items.${index}.review_state`, "accepted", {
      shouldDirty: true,
    });
  }

  function handleTriggerClick() {
    if (unreviewedCount > 0) {
      onRegenerateNeeded();
    } else {
      suggestion.suggest();
    }
  }

  const lineItemsMessage =
    typeof errors.line_items?.message === "string"
      ? errors.line_items.message
      : errors.line_items?.root?.message;

  // The trigger is a legitimate non-finance surface with a missing
  // affordance rather than a denial panel — a viewer without finance.view
  // simply never sees the button (D-10, UI-SPEC state 2).
  const showTrigger =
    canViewFinance && (isNewQuote || quote?.status === "draft");
  const disabledReason = triggerDisabledReason({ isNewQuote, isDirty });

  // Project-level quote only: job_id and trade_scope_id are both null, so
  // there is no anchor to source the trade from and `field` needs its own
  // input. Job- and scope-anchored quotes carry `field` as a hidden value.
  const showTradeColumn =
    !!quote && quote.job_id === null && (quote.trade_scope_id ?? null) === null;

  const columns = showTradeColumn
    ? [...BASE_COLUMN_HEADERS, TRADE_COLUMN_HEADER, TOTAL_COLUMN_HEADER]
    : [...BASE_COLUMN_HEADERS, TOTAL_COLUMN_HEADER];
  const columnCount = columns.length + 2; // drag handle + delete
  const tableMinWidthClass = showTradeColumn ? "min-w-[840px]" : "min-w-[700px]";

  const watchedItems = watch("line_items");
  const hasAiLaborLine = watchedItems.some(
    (item) => item.ai_origin && item.item_type === "labor"
  );

  return (
    <Card>
      <CardHeader className="flex items-center justify-between">
        <CardTitle>Line Items</CardTitle>
        {showTrigger && (
          <SuggestTrigger
            aiLineCount={aiLineCount}
            isPending={suggestion.isPending}
            disabledReason={disabledReason}
            onClick={handleTriggerClick}
          />
        )}
      </CardHeader>
      <CardContent>
        {suggestion.refusal?.refusalReason && (
          <div className="mb-4">
            <SuggestionNotice
              reason={suggestion.refusal.refusalReason}
              context={suggestion.refusal}
            />
          </div>
        )}
        {unreviewedCount > 0 && (
          <div className="mb-4">
            <UnreviewedBanner count={unreviewedCount} />
          </div>
        )}

        {fields.length === 0 ? (
          <p className="text-sm text-gray-500 py-4 text-center">
            No line items yet. Click Add Row to start building your quote.
          </p>
        ) : (
          <DndContext
            id={dndContextId}
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={handleDragEnd}
          >
            <div className="overflow-x-auto">
              <table className={`w-full ${tableMinWidthClass} text-sm`}>
                <thead>
                  <tr className="border-b border-gray-200">
                    <th className="w-8" />
                    {columns.map((header) => (
                      <th
                        key={header.label}
                        className={`${header.alignClass} py-2 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wide ${header.width ?? ""}`}
                      >
                        {header.label}
                      </th>
                    ))}
                    <th className="w-8" />
                  </tr>
                </thead>
                <tbody>
                  <SortableContext
                    items={fields.map((f) => f.id)}
                    strategy={verticalListSortingStrategy}
                  >
                    {fields.map((field, index) => {
                      const item = watchedItems[index];
                      return (
                        <Fragment key={field.id}>
                          <SortableLineItemRow
                            fieldId={field.id}
                            index={index}
                            isLast={index === fields.length - 1}
                            onRemove={() => remove(index)}
                            onAppendRow={appendRow}
                            register={register}
                            control={control}
                            watch={watch}
                            errors={errors}
                            showTradeColumn={showTradeColumn}
                          />
                          {item?.ai_origin && (
                            <AiLineSubRow
                              index={index}
                              columnCount={columnCount}
                              band={item.confidence_band ?? null}
                              reviewState={item.review_state ?? "unreviewed"}
                              basis={item.basis ?? null}
                              onAccept={() => handleAccept(index)}
                            />
                          )}
                        </Fragment>
                      );
                    })}
                  </SortableContext>
                </tbody>
              </table>
            </div>
          </DndContext>
        )}

        <div className="mt-3">
          <Button type="button" variant="outline" size="sm" onClick={appendRow}>
            <Plus className="h-4 w-4 mr-2" />
            Add Row
          </Button>
        </div>

        {lineItemsMessage && (
          <p className="text-xs text-red-500 mt-2">{lineItemsMessage}</p>
        )}

        <CardCaptions
          aiLineCount={aiLineCount}
          canViewFinance={canViewFinance}
          hasLaborLine={hasAiLaborLine}
        />
      </CardContent>
    </Card>
  );
}

function SuggestTrigger({
  aiLineCount,
  isPending,
  disabledReason,
  onClick,
}: {
  aiLineCount: number;
  isPending: boolean;
  disabledReason: string | null;
  onClick: () => void;
}) {
  return (
    <div className="flex flex-col items-end gap-1">
      <Button
        type="button"
        variant="outline"
        size="sm"
        data-testid="suggest-line-items-trigger"
        disabled={isPending || disabledReason !== null}
        onClick={onClick}
      >
        <Bot className="h-4 w-4 mr-2" />
        {triggerLabel(aiLineCount, isPending)}
      </Button>
      {disabledReason && (
        <p data-testid="suggest-trigger-reason" className="text-xs text-gray-500">
          {disabledReason}
        </p>
      )}
    </div>
  );
}

function CardCaptions({
  aiLineCount,
  canViewFinance,
  hasLaborLine,
}: {
  aiLineCount: number;
  canViewFinance: boolean;
  hasLaborLine: boolean;
}) {
  if (aiLineCount === 0) return null;

  return (
    <div className="mt-4 space-y-1 text-xs text-gray-500">
      {canViewFinance && (
        <p data-testid="quote-pricing-basis-note">{PRICING_BASIS_CAPTION}</p>
      )}
      {hasLaborLine && (
        <p data-testid="quote-labor-note">{UNBURDENED_LABOR_CAPTION}</p>
      )}
      <p data-testid="quote-ai-disclosure">{AI_DISCLOSURE_NOTE}</p>
    </div>
  );
}
