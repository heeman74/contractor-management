import { useId } from "react";
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
import { Plus } from "lucide-react";
import {
  useFieldArray,
  type UseFormReturn,
} from "react-hook-form";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { SortableLineItemRow } from "./sortable-line-item-row";
import { createEmptyLineItem, type QuoteFormValues } from "../_lib/quote-form";

const COLUMN_HEADERS: Array<{ label: string; alignClass: string; width?: string }> = [
  { label: "Type", alignClass: "text-left", width: "w-[120px]" },
  { label: "Description", alignClass: "text-left" },
  { label: "Qty", alignClass: "text-right", width: "w-[72px]" },
  { label: "Unit", alignClass: "text-left", width: "w-[80px]" },
  { label: "Unit Price", alignClass: "text-right", width: "w-[112px]" },
  { label: "Total", alignClass: "text-right", width: "w-[96px]" },
];

interface LineItemsTableProps {
  form: UseFormReturn<QuoteFormValues>;
}

export function LineItemsTable({ form }: LineItemsTableProps) {
  const {
    control,
    register,
    watch,
    formState: { errors },
  } = form;

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

  const lineItemsMessage =
    typeof errors.line_items?.message === "string"
      ? errors.line_items.message
      : errors.line_items?.root?.message;

  return (
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
          <DndContext
            id={dndContextId}
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragEnd={handleDragEnd}
          >
            <div className="overflow-x-auto">
              <table className="w-full min-w-[700px] text-sm">
                <thead>
                  <tr className="border-b border-gray-200">
                    <th className="w-8" />
                    {COLUMN_HEADERS.map((header) => (
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
                    {fields.map((field, index) => (
                      <SortableLineItemRow
                        key={field.id}
                        fieldId={field.id}
                        index={index}
                        isLast={index === fields.length - 1}
                        onRemove={() => remove(index)}
                        onAppendRow={appendRow}
                        register={register}
                        control={control}
                        watch={watch}
                        errors={errors}
                      />
                    ))}
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
      </CardContent>
    </Card>
  );
}
