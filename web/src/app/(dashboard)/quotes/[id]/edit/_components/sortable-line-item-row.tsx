import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { GripVertical, X } from "lucide-react";
import { Controller, type UseFormReturn } from "react-hook-form";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { computeLineTotal, type QuoteFormValues } from "../_lib/quote-form";

interface SortableLineItemRowProps {
  fieldId: string;
  index: number;
  isLast: boolean;
  onRemove: () => void;
  onAppendRow: () => void;
  register: UseFormReturn<QuoteFormValues>["register"];
  control: UseFormReturn<QuoteFormValues>["control"];
  watch: UseFormReturn<QuoteFormValues>["watch"];
  errors: UseFormReturn<QuoteFormValues>["formState"]["errors"];
  showTradeColumn?: boolean;
}

export function SortableLineItemRow({
  fieldId,
  index,
  isLast,
  onRemove,
  onAppendRow,
  register,
  control,
  watch,
  errors,
  showTradeColumn = false,
}: SortableLineItemRowProps) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } =
    useSortable({ id: fieldId });

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
  };

  const lineTotal = computeLineTotal({
    quantity: watch(`line_items.${index}.quantity`),
    unit_price: watch(`line_items.${index}.unit_price`),
  }).toFixed(2);

  const lineErrors = errors.line_items?.[index];

  const isUnreviewedAiLine =
    watch(`line_items.${index}.ai_origin`) === true &&
    watch(`line_items.${index}.review_state`) === "unreviewed";

  const rowTintClass = isDragging
    ? "opacity-50 bg-blue-50"
    : isUnreviewedAiLine
      ? "bg-secondary"
      : "";

  return (
    <tr
      ref={setNodeRef}
      style={style}
      className={`border-b border-gray-100 ${rowTintClass}`}
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
            <Select value={field.value} onValueChange={(v) => field.onChange(v)}>
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
          <p className="text-xs text-red-500 mt-0.5">
            {lineErrors.description.message}
          </p>
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
          <span className="absolute left-2 text-xs text-gray-500 pointer-events-none">
            $
          </span>
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

      {/* Trade — project-level quotes only; job/scope-anchored quotes carry
          `field` as a hidden value derived from their anchor. */}
      {showTradeColumn && (
        <td className="px-1 py-2 w-[140px]">
          <Input
            {...register(`line_items.${index}.field`)}
            placeholder="e.g. Plumbing"
            className="w-[140px] text-sm"
          />
        </td>
      )}

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
