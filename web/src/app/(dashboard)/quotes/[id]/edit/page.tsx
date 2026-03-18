"use client";

import { use, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useForm, useFieldArray, Controller } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { toast } from "sonner";
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
  useSortable,
} from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { GripVertical, X, Plus } from "lucide-react";
import { apiGet, apiPost, apiPatch, ApiError } from "@/lib/api-client";
import type { Quote, QuoteTemplate } from "@/types/api";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
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

// ---------------------------------------------------------------------------
// Zod schema
// ---------------------------------------------------------------------------

const lineItemSchema = z.object({
  item_type: z.enum(["labor", "material"]),
  description: z.string().min(1, "Required").max(500),
  quantity: z.string().refine((v) => Number(v) > 0, "Must be > 0"),
  unit: z.string().min(1, "Required").max(50),
  unit_price: z.string().refine((v) => Number(v) >= 0, "Must be >= 0"),
  sort_order: z.number(),
});

const quoteFormSchema = z.object({
  line_items: z.array(lineItemSchema).min(1, "At least one line item required"),
  tax_rate: z
    .string()
    .refine(
      (v) => { const n = Number(v); return n >= 0 && n <= 100; },
      "0-100"
    ),
  discount_type: z.enum(["percent", "fixed"]).nullable(),
  discount_value: z.string(),
  expiry_date: z.string().nullable(),
  admin_notes: z.string().nullable(),
});

type QuoteFormValues = z.infer<typeof quoteFormSchema>;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function mapQuoteToFormValues(quote: Quote): QuoteFormValues {
  return {
    line_items: quote.line_items.map((item) => ({
      item_type: item.item_type,
      description: item.description,
      quantity: item.quantity,
      unit: item.unit,
      unit_price: item.unit_price,
      sort_order: item.sort_order,
    })),
    tax_rate: quote.tax_rate,
    discount_type: quote.discount_type,
    discount_value: quote.discount_value,
    expiry_date: quote.expiry_date,
    admin_notes: quote.admin_notes,
  };
}

const DEFAULT_FORM_VALUES: QuoteFormValues = {
  line_items: [
    {
      item_type: "labor",
      description: "",
      quantity: "1",
      unit: "hr",
      unit_price: "0",
      sort_order: 0,
    },
  ],
  tax_rate: "0",
  discount_type: null,
  discount_value: "0",
  expiry_date: null,
  admin_notes: null,
};

// ---------------------------------------------------------------------------
// Sortable row component
// ---------------------------------------------------------------------------

interface SortableRowProps {
  fieldId: string;
  index: number;
  isLast: boolean;
  onRemove: () => void;
  onAppendRow: () => void;
  register: ReturnType<typeof useForm<QuoteFormValues>>["register"];
  control: ReturnType<typeof useForm<QuoteFormValues>>["control"];
  watch: ReturnType<typeof useForm<QuoteFormValues>>["watch"];
  errors: ReturnType<typeof useForm<QuoteFormValues>>["formState"]["errors"];
}

function SortableRow({
  fieldId,
  index,
  isLast,
  onRemove,
  onAppendRow,
  register,
  control,
  watch,
  errors,
}: SortableRowProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: fieldId });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  const qty = watch(`line_items.${index}.quantity`);
  const price = watch(`line_items.${index}.unit_price`);
  const lineTotal = ((Number(qty) || 0) * (Number(price) || 0)).toFixed(2);

  const lineErrors = errors.line_items?.[index];

  return (
    <tr
      ref={setNodeRef}
      style={style}
      className={`border-b border-gray-100 ${isDragging ? "opacity-50 bg-blue-50" : ""}`}
    >
      {/* Drag handle */}
      <td className="w-8 px-1 py-2">
        <button
          type="button"
          className="cursor-grab active:cursor-grabbing touch-none p-0.5 rounded hover:bg-gray-100"
          {...attributes}
          {...listeners}
          aria-label="Drag to reorder"
        >
          <GripVertical className="h-4 w-4 text-gray-400" />
        </button>
      </td>

      {/* Type */}
      <td className="px-1 py-2 w-[120px]">
        <Controller
          control={control}
          name={`line_items.${index}.item_type`}
          render={({ field }) => (
            <Select
              value={field.value}
              onValueChange={(v) => field.onChange(v)}
            >
              <SelectTrigger className="w-[110px] text-xs">
                <SelectValue placeholder="Type" />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="labor">Labor</SelectItem>
                <SelectItem value="material">Material</SelectItem>
              </SelectContent>
            </Select>
          )}
        />
      </td>

      {/* Description */}
      <td className="px-1 py-2 min-w-[160px]">
        <Input
          {...register(`line_items.${index}.description`)}
          placeholder="Description"
          className={`min-w-[160px] text-sm ${lineErrors?.description ? "border-red-400" : ""}`}
          aria-invalid={!!lineErrors?.description}
        />
        {lineErrors?.description && (
          <p className="text-xs text-red-500 mt-0.5">{lineErrors.description.message}</p>
        )}
      </td>

      {/* Qty */}
      <td className="px-1 py-2 w-[72px]">
        <Input
          type="number"
          step="0.001"
          min="0.001"
          {...register(`line_items.${index}.quantity`)}
          className={`w-[72px] text-right text-sm ${lineErrors?.quantity ? "border-red-400" : ""}`}
          aria-invalid={!!lineErrors?.quantity}
        />
      </td>

      {/* Unit */}
      <td className="px-1 py-2 w-[80px]">
        <Input
          {...register(`line_items.${index}.unit`)}
          placeholder="hr"
          className={`w-[80px] text-sm ${lineErrors?.unit ? "border-red-400" : ""}`}
          aria-invalid={!!lineErrors?.unit}
        />
      </td>

      {/* Unit Price */}
      <td className="px-1 py-2 w-[112px]">
        <div className="relative flex items-center">
          <span className="absolute left-2 text-xs text-gray-500 pointer-events-none">$</span>
          <Input
            type="number"
            step="0.01"
            min="0"
            {...register(`line_items.${index}.unit_price`)}
            className={`w-[96px] text-right pl-5 text-sm ${lineErrors?.unit_price ? "border-red-400" : ""}`}
            aria-invalid={!!lineErrors?.unit_price}
            onKeyDown={
              isLast
                ? (e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      onAppendRow();
                    }
                  }
                : undefined
            }
          />
        </div>
      </td>

      {/* Total (computed) */}
      <td className="px-1 py-2 w-[96px] text-right">
        <span className="font-mono text-sm text-gray-900">${lineTotal}</span>
      </td>

      {/* Delete */}
      <td className="px-1 py-2 w-8">
        <Button
          type="button"
          variant="ghost"
          size="icon"
          onClick={onRemove}
          aria-label="Delete row"
          className="h-7 w-7"
        >
          <X className="h-4 w-4" />
        </Button>
      </td>
    </tr>
  );
}

// ---------------------------------------------------------------------------
// Preview component
// ---------------------------------------------------------------------------

interface PreviewProps {
  values: QuoteFormValues;
  revisionNumber?: number;
}

function QuotePreview({ values, revisionNumber = 1 }: PreviewProps) {
  const subtotal = values.line_items.reduce(
    (sum, item) => sum + (Number(item.quantity) || 0) * (Number(item.unit_price) || 0),
    0
  );
  const discountAmount =
    values.discount_type === "percent"
      ? (subtotal * Number(values.discount_value)) / 100
      : values.discount_type === "fixed"
      ? Math.min(Number(values.discount_value), subtotal)
      : 0;
  const taxAmount = ((subtotal - discountAmount) * Number(values.tax_rate)) / 100;
  const total = subtotal - discountAmount + taxAmount;

  return (
    <div className="bg-white p-8 shadow-sm rounded-xl max-w-3xl mx-auto">
      {/* Header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <h2 className="text-2xl font-bold text-gray-900">QUOTE</h2>
          <p className="text-sm text-gray-500 mt-1">v{revisionNumber}</p>
        </div>
        <div className="text-right text-sm text-gray-600">
          <p className="font-semibold text-gray-800">Your Company Name</p>
          {values.expiry_date && (
            <p className="mt-1 text-xs text-gray-400">
              Expires:{" "}
              {new Date(values.expiry_date).toLocaleDateString()}
            </p>
          )}
        </div>
      </div>

      {/* Line items table */}
      <table className="w-full mb-6 text-sm">
        <thead>
          <tr className="border-b-2 border-gray-200">
            <th className="text-left py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Type
            </th>
            <th className="text-left py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Description
            </th>
            <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Qty
            </th>
            <th className="text-left py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Unit
            </th>
            <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Unit Price
            </th>
            <th className="text-right py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              Total
            </th>
          </tr>
        </thead>
        <tbody>
          {values.line_items.map((item, idx) => {
            const lineTotal =
              (Number(item.quantity) || 0) * (Number(item.unit_price) || 0);
            return (
              <tr key={idx} className="border-b border-gray-100">
                <td className="py-2 text-xs capitalize text-gray-600">
                  {item.item_type}
                </td>
                <td className="py-2 text-sm text-gray-700">{item.description}</td>
                <td className="py-2 font-mono text-right text-gray-900">
                  {item.quantity}
                </td>
                <td className="py-2 text-sm text-gray-500">{item.unit}</td>
                <td className="py-2 font-mono text-right text-gray-900">
                  ${Number(item.unit_price).toFixed(2)}
                </td>
                <td className="py-2 font-mono text-right text-gray-900">
                  ${lineTotal.toFixed(2)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>

      {/* Financial summary */}
      <div className="space-y-1 max-w-xs ml-auto">
        <div className="flex justify-between text-sm text-gray-600">
          <span>Subtotal</span>
          <span className="font-mono">${subtotal.toFixed(2)}</span>
        </div>
        {discountAmount > 0 && (
          <div className="flex justify-between text-sm text-gray-600">
            <span>
              Discount
              {values.discount_type === "percent"
                ? ` (${values.discount_value}%)`
                : ""}
            </span>
            <span className="font-mono text-red-600">
              -${discountAmount.toFixed(2)}
            </span>
          </div>
        )}
        <div className="flex justify-between text-sm text-gray-600">
          <span>Tax ({values.tax_rate}%)</span>
          <span className="font-mono">${taxAmount.toFixed(2)}</span>
        </div>
        <div className="flex justify-between text-base font-bold text-gray-900 pt-1 border-t">
          <span>Total</span>
          <span className="font-mono">${total.toFixed(2)}</span>
        </div>
      </div>

      {/* Admin notes (preview only for admin) */}
      {values.admin_notes && (
        <div className="mt-6 border-t pt-4">
          <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1">
            Admin Notes
          </p>
          <p className="text-sm text-gray-600 whitespace-pre-wrap">
            {values.admin_notes}
          </p>
        </div>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main page
// ---------------------------------------------------------------------------

export default function QuoteEditPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = use(params);
  const router = useRouter();
  const searchParams = useSearchParams();
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  const isNew = id === "new";
  const isRevise = searchParams.get("revise") === "true";
  const jobIdParam = searchParams.get("job_id");

  const [mode, setMode] = useState<"edit" | "preview">("edit");
  const [templateConfirmOpen, setTemplateConfirmOpen] = useState(false);
  const [pendingTemplate, setPendingTemplate] = useState<QuoteTemplate | null>(null);

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  const { data: existingQuote, isLoading: quoteLoading } = useQuery<Quote>({
    queryKey: ["quote", id],
    queryFn: () => apiGet<Quote>(`/api/v1/quotes/${id}`),
    enabled: !isNew,
  });

  const { data: templates = [] } = useQuery<QuoteTemplate[]>({
    queryKey: ["quote-templates"],
    queryFn: () => apiGet<QuoteTemplate[]>("/api/v1/quotes/templates"),
  });

  // ---------------------------------------------------------------------------
  // Form setup
  // ---------------------------------------------------------------------------

  const {
    control,
    register,
    watch,
    handleSubmit,
    getValues,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<QuoteFormValues>({
    resolver: zodResolver(quoteFormSchema),
    defaultValues: DEFAULT_FORM_VALUES,
  });

  // Populate form when existing quote loads (avoid setValue-on-mount pitfall)
  useEffect(() => {
    if (existingQuote) {
      reset(mapQuoteToFormValues(existingQuote));
    }
  }, [existingQuote, reset]);

  const { fields, append, remove, move } = useFieldArray({
    control,
    name: "line_items",
  });

  // ---------------------------------------------------------------------------
  // DnD
  // ---------------------------------------------------------------------------

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } })
  );

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (active.id !== over?.id) {
      const oldIndex = fields.findIndex((f) => f.id === active.id);
      const newIndex = fields.findIndex((f) => f.id === over!.id);
      move(oldIndex, newIndex);
    }
  }

  // ---------------------------------------------------------------------------
  // Derived values (live financial summary)
  // ---------------------------------------------------------------------------

  const lineItems = watch("line_items");
  const taxRate = watch("tax_rate");
  const discountType = watch("discount_type");
  const discountValue = watch("discount_value");

  const subtotal = lineItems.reduce(
    (sum, item) =>
      sum + (Number(item.quantity) || 0) * (Number(item.unit_price) || 0),
    0
  );
  const discountAmount =
    discountType === "percent"
      ? (subtotal * Number(discountValue)) / 100
      : discountType === "fixed"
      ? Math.min(Number(discountValue), subtotal)
      : 0;
  const taxAmount = ((subtotal - discountAmount) * Number(taxRate)) / 100;
  const total = subtotal - discountAmount + taxAmount;

  // ---------------------------------------------------------------------------
  // Page title
  // ---------------------------------------------------------------------------

  useEffect(() => {
    if (isNew) dispatch(setPageTitle("New Quote"));
    else if (isRevise && existingQuote)
      dispatch(
        setPageTitle(`Revise Quote — v${existingQuote.revision_number + 1}`)
      );
    else if (existingQuote)
      dispatch(
        setPageTitle(`Edit Quote — v${existingQuote.revision_number}`)
      );
    return () => {
      dispatch(setPageTitle(null));
    };
  }, [isNew, isRevise, existingQuote, dispatch]);

  // ---------------------------------------------------------------------------
  // Template loading
  // ---------------------------------------------------------------------------

  function applyTemplate(template: QuoteTemplate) {
    try {
      const parsedItems = JSON.parse(template.line_items_json) as Array<{
        item_type: "labor" | "material";
        description: string;
        quantity: string | number;
        unit: string;
        unit_price: string | number;
        sort_order?: number;
      }>;
      const mappedItems = parsedItems.map((item, i) => ({
        item_type: item.item_type,
        description: item.description,
        quantity: String(item.quantity),
        unit: item.unit,
        unit_price: String(item.unit_price),
        sort_order: item.sort_order ?? i,
      }));
      reset({
        ...getValues(),
        line_items: mappedItems,
        tax_rate: template.tax_rate,
      });
    } catch {
      toast.error("Failed to load template. Invalid template data.", {
        duration: Infinity,
      });
    }
  }

  function handleTemplateSelect(templateId: string) {
    const template = templates.find((t) => t.id === templateId);
    if (!template) return;
    if (fields.length > 0 && (fields.length > 1 || lineItems[0]?.description)) {
      setPendingTemplate(template);
      setTemplateConfirmOpen(true);
    } else {
      applyTemplate(template);
    }
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------

  const jobId = isNew ? (jobIdParam ?? "") : (existingQuote?.job_id ?? "");

  function buildPayload(data: QuoteFormValues) {
    return {
      tax_rate: data.tax_rate,
      discount_type: data.discount_type,
      discount_value: data.discount_value,
      expiry_date: data.expiry_date,
      admin_notes: data.admin_notes,
      line_items: data.line_items.map((item, i) => ({
        item_type: item.item_type,
        description: item.description,
        quantity: item.quantity,
        unit: item.unit,
        unit_price: item.unit_price,
        sort_order: i,
      })),
    };
  }

  const createMutation = useMutation({
    mutationFn: (data: QuoteFormValues) =>
      apiPost<Quote>("/api/v1/quotes/", { job_id: jobId, ...buildPayload(data) }),
    onSuccess: (quote) => {
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Quote saved as draft");
      router.push(`/quotes/${quote.id}`);
    },
    onError: (err: Error) => {
      const detail = err instanceof ApiError ? err.detail : "Try again.";
      toast.error(`Failed to save quote. ${detail}`, { duration: Infinity });
    },
  });

  const updateMutation = useMutation({
    mutationFn: (data: QuoteFormValues) =>
      apiPatch<Quote>(`/api/v1/quotes/${id}`, buildPayload(data)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["quote", id] });
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Quote updated");
      router.push(`/quotes/${id}`);
    },
    onError: (err: Error) => {
      const detail = err instanceof ApiError ? err.detail : "Try again.";
      toast.error(`Failed to update quote. ${detail}`, { duration: Infinity });
    },
  });

  const reviseMutation = useMutation({
    mutationFn: (data: QuoteFormValues) =>
      apiPost<Quote>(`/api/v1/quotes/${id}/revise`, buildPayload(data)),
    onSuccess: (newQuote) => {
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Revision created");
      router.push(`/quotes/${newQuote.id}`);
    },
    onError: (err: Error) => {
      const detail = err instanceof ApiError ? err.detail : "Try again.";
      toast.error(`Failed to create revision. ${detail}`, { duration: Infinity });
    },
  });

  const isMutating =
    createMutation.isPending ||
    updateMutation.isPending ||
    reviseMutation.isPending;

  function onSubmit(data: QuoteFormValues) {
    if (isRevise) reviseMutation.mutate(data);
    else if (isNew) createMutation.mutate(data);
    else updateMutation.mutate(data);
  }

  // ---------------------------------------------------------------------------
  // Loading state
  // ---------------------------------------------------------------------------

  if (!isNew && quoteLoading) {
    return (
      <div className="space-y-4 animate-pulse">
        <div className="h-8 w-1/3 rounded bg-gray-200" />
        <div className="h-64 rounded-xl bg-gray-100" />
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // Page heading
  // ---------------------------------------------------------------------------

  const pageTitle = isNew
    ? "New Quote"
    : isRevise && existingQuote
    ? `Revise Quote — v${existingQuote.revision_number + 1}`
    : existingQuote
    ? `Edit Quote — v${existingQuote.revision_number}`
    : "Edit Quote";

  const revisionNumber = isRevise
    ? (existingQuote?.revision_number ?? 1) + 1
    : existingQuote?.revision_number ?? 1;

  // ---------------------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------------------

  return (
    <div className="space-y-6 pb-24">
      {/* Page header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-xl font-semibold text-gray-900">{pageTitle}</h1>
        <div className="flex items-center gap-3 flex-wrap">
          {/* Template loader */}
          {templates.length > 0 && (
            <Select<string> onValueChange={(v) => { if (v) handleTemplateSelect(v); }}>
              <SelectTrigger className="w-[200px] text-sm">
                <SelectValue placeholder="Load from template..." />
              </SelectTrigger>
              <SelectContent>
                {templates.map((t) => (
                  <SelectItem key={t.id} value={t.id}>
                    {t.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )}

          {/* Edit / Preview tabs */}
          <Tabs
            value={mode}
            onValueChange={(v) => setMode(v as "edit" | "preview")}
          >
            <TabsList>
              <TabsTrigger value="edit">Edit</TabsTrigger>
              <TabsTrigger value="preview">Preview</TabsTrigger>
            </TabsList>
          </Tabs>
        </div>
      </div>

      {/* Form */}
      <form onSubmit={handleSubmit(onSubmit)}>
        {mode === "edit" ? (
          <div className="space-y-6">
            {/* Line items card */}
            <Card>
              <CardHeader>
                <CardTitle>Line Items</CardTitle>
              </CardHeader>
              <CardContent>
                {fields.length === 0 ? (
                  <p className="text-sm text-gray-500 py-4 text-center">
                    No line items yet. Click Add Row to start building your quote.
                  </p>
                ) : (
                  <div className="overflow-x-auto">
                    <table className="w-full min-w-[700px] text-sm">
                      <thead>
                        <tr className="border-b border-gray-200">
                          <th className="w-8" />
                          <th className="text-left py-2 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wide w-[120px]">
                            Type
                          </th>
                          <th className="text-left py-2 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wide">
                            Description
                          </th>
                          <th className="text-right py-2 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wide w-[72px]">
                            Qty
                          </th>
                          <th className="text-left py-2 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wide w-[80px]">
                            Unit
                          </th>
                          <th className="text-right py-2 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wide w-[112px]">
                            Unit Price
                          </th>
                          <th className="text-right py-2 px-1 text-xs font-semibold text-gray-500 uppercase tracking-wide w-[96px]">
                            Total
                          </th>
                          <th className="w-8" />
                        </tr>
                      </thead>
                      <tbody>
                        <DndContext
                          sensors={sensors}
                          collisionDetection={closestCenter}
                          onDragEnd={handleDragEnd}
                        >
                          <SortableContext
                            items={fields.map((f) => f.id)}
                            strategy={verticalListSortingStrategy}
                          >
                            {fields.map((field, index) => (
                              <SortableRow
                                key={field.id}
                                fieldId={field.id}
                                index={index}
                                isLast={index === fields.length - 1}
                                onRemove={() => remove(index)}
                                onAppendRow={() =>
                                  append({
                                    item_type: "labor",
                                    description: "",
                                    quantity: "1",
                                    unit: "hr",
                                    unit_price: "0",
                                    sort_order: fields.length,
                                  })
                                }
                                register={register}
                                control={control}
                                watch={watch}
                                errors={errors}
                              />
                            ))}
                          </SortableContext>
                        </DndContext>
                      </tbody>
                    </table>
                  </div>
                )}

                {/* Add Row button */}
                <div className="mt-3">
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      append({
                        item_type: "labor",
                        description: "",
                        quantity: "1",
                        unit: "hr",
                        unit_price: "0",
                        sort_order: fields.length,
                      })
                    }
                  >
                    <Plus className="h-4 w-4 mr-2" />
                    Add Row
                  </Button>
                </div>

                {/* Line items array error */}
                {errors.line_items?.root && (
                  <p className="text-xs text-red-500 mt-2">
                    {errors.line_items.root.message}
                  </p>
                )}
                {typeof errors.line_items?.message === "string" && (
                  <p className="text-xs text-red-500 mt-2">
                    {errors.line_items.message}
                  </p>
                )}
              </CardContent>
            </Card>

            {/* Settings card (discount, tax, expiry, notes) */}
            <Card>
              <CardHeader>
                <CardTitle>Quote Settings</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                  {/* Tax rate */}
                  <div className="space-y-1">
                    <label className="text-xs font-semibold text-gray-700">
                      Tax Rate
                    </label>
                    <div className="flex items-center gap-1.5">
                      <Input
                        type="number"
                        step="0.01"
                        min="0"
                        max="100"
                        {...register("tax_rate")}
                        className={`w-[80px] text-right ${errors.tax_rate ? "border-red-400" : ""}`}
                        aria-invalid={!!errors.tax_rate}
                      />
                      <span className="text-sm text-gray-500">%</span>
                    </div>
                    {errors.tax_rate && (
                      <p className="text-xs text-red-500">
                        {errors.tax_rate.message}
                      </p>
                    )}
                  </div>

                  {/* Expiry date */}
                  <div className="space-y-1">
                    <label className="text-xs font-semibold text-gray-700">
                      Expiry Date
                    </label>
                    <Controller
                      control={control}
                      name="expiry_date"
                      render={({ field }) => (
                        <input
                          type="date"
                          className="h-8 rounded-lg border border-input bg-transparent px-2.5 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-500 w-full max-w-[200px]"
                          value={field.value ?? ""}
                          onChange={(e) =>
                            field.onChange(e.target.value || null)
                          }
                          min={new Date().toISOString().split("T")[0]}
                        />
                      )}
                    />
                  </div>

                  {/* Discount type */}
                  <div className="space-y-1">
                    <label className="text-xs font-semibold text-gray-700">
                      Discount Type
                    </label>
                    <Controller
                      control={control}
                      name="discount_type"
                      render={({ field }) => (
                        <Select
                          value={field.value ?? "none"}
                          onValueChange={(v) =>
                            field.onChange(v === "none" ? null : v)
                          }
                        >
                          <SelectTrigger className="w-[160px]">
                            <SelectValue placeholder="No discount" />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="none">None</SelectItem>
                            <SelectItem value="percent">Percent (%)</SelectItem>
                            <SelectItem value="fixed">Fixed ($)</SelectItem>
                          </SelectContent>
                        </Select>
                      )}
                    />
                  </div>

                  {/* Discount value */}
                  {discountType && (
                    <div className="space-y-1">
                      <label className="text-xs font-semibold text-gray-700">
                        Discount Value
                      </label>
                      <div className="flex items-center gap-1.5">
                        {discountType === "fixed" && (
                          <span className="text-sm text-gray-500">$</span>
                        )}
                        <Input
                          type="number"
                          step="0.01"
                          min="0"
                          {...register("discount_value")}
                          className="w-[96px] text-right"
                        />
                        {discountType === "percent" && (
                          <span className="text-sm text-gray-500">%</span>
                        )}
                      </div>
                    </div>
                  )}
                </div>

                {/* Admin notes */}
                <div className="mt-6 space-y-1">
                  <label className="text-xs font-semibold text-gray-700">
                    Admin Notes
                  </label>
                  <Controller
                    control={control}
                    name="admin_notes"
                    render={({ field }) => (
                      <Textarea
                        placeholder="Internal notes (not visible to client)..."
                        className="resize-none"
                        rows={3}
                        value={field.value ?? ""}
                        onChange={(e) =>
                          field.onChange(e.target.value || null)
                        }
                      />
                    )}
                  />
                </div>
              </CardContent>
            </Card>
          </div>
        ) : (
          /* Preview mode */
          <QuotePreview values={getValues()} revisionNumber={revisionNumber} />
        )}

        {/* Form footer (below content, above sticky bar) */}
        <div className="mt-6 flex items-center justify-end gap-3">
          <Button
            type="button"
            variant="ghost"
            onClick={() => {
              if (isNew) router.back();
              else router.push(`/quotes/${id}`);
            }}
            disabled={isMutating || isSubmitting}
          >
            Discard Changes
          </Button>
          <Button type="submit" disabled={isMutating || isSubmitting}>
            {isMutating ? "Saving..." : "Save Draft"}
          </Button>
        </div>
      </form>

      {/* -------------------------------------------------------------------- */}
      {/* Template replace confirmation dialog                                  */}
      {/* -------------------------------------------------------------------- */}
      <Dialog open={templateConfirmOpen} onOpenChange={setTemplateConfirmOpen}>
        <DialogContent showCloseButton>
          <DialogHeader>
            <DialogTitle>Replace current line items with template?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-gray-600">
            This will replace your existing line items with the template
            &ldquo;{pendingTemplate?.name}&rdquo;. This action cannot be undone.
          </p>
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                setTemplateConfirmOpen(false);
                setPendingTemplate(null);
              }}
            >
              Cancel
            </Button>
            <Button
              onClick={() => {
                if (pendingTemplate) applyTemplate(pendingTemplate);
                setTemplateConfirmOpen(false);
                setPendingTemplate(null);
              }}
            >
              Replace Line Items
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* -------------------------------------------------------------------- */}
      {/* Sticky financial summary footer                                       */}
      {/* -------------------------------------------------------------------- */}
      <div className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-200 px-6 py-3 z-40">
        <div className="flex items-center justify-end gap-6 max-w-screen-2xl mx-auto">
          <div className="flex items-center gap-1.5">
            <span className="text-xs text-gray-500 uppercase tracking-wide">
              Subtotal
            </span>
            <span className="text-sm font-mono font-semibold text-gray-900">
              ${subtotal.toFixed(2)}
            </span>
          </div>
          {discountAmount > 0 && (
            <div className="flex items-center gap-1.5">
              <span className="text-xs text-gray-500 uppercase tracking-wide">
                Discount
              </span>
              <span className="text-sm font-mono font-semibold text-red-600">
                -${discountAmount.toFixed(2)}
              </span>
            </div>
          )}
          <div className="flex items-center gap-1.5">
            <span className="text-xs text-gray-500 uppercase tracking-wide">
              Tax
            </span>
            <span className="text-sm font-mono font-semibold text-gray-900">
              ${taxAmount.toFixed(2)}
            </span>
          </div>
          <div className="flex items-center gap-1.5 border-l border-gray-200 pl-6">
            <span className="text-xs text-gray-500 uppercase tracking-wide">
              Total
            </span>
            <span className="text-base font-mono font-semibold text-gray-900">
              ${total.toFixed(2)}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
