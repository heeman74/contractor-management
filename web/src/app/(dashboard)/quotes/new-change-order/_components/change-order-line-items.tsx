"use client";

import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { ChangeOrderItem, ChangeOrderItemType } from "../_lib/change-order";

interface ChangeOrderLineRowProps {
  item: ChangeOrderItem;
  isRemovable: boolean;
  onPatch: (patch: Partial<ChangeOrderItem>) => void;
  onRemove: () => void;
}

/** One priced row. Every input carries an aria-label because the row's columns
 *  have no visible headings to associate with. */
function ChangeOrderLineRow({
  item,
  isRemovable,
  onPatch,
  onRemove,
}: ChangeOrderLineRowProps) {
  return (
    <div className="flex items-end gap-2">
      <div className="w-[110px]">
        <Select
          value={item.item_type}
          onValueChange={(value) => {
            if (value) onPatch({ item_type: value as ChangeOrderItemType });
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
        onChange={(event) => onPatch({ description: event.target.value })}
        placeholder="Description"
        className="flex-1"
      />
      <Input
        aria-label="Quantity"
        type="number"
        min="0"
        step="0.5"
        value={item.quantity}
        onChange={(event) => onPatch({ quantity: event.target.value })}
        className="w-[72px]"
      />
      <Input
        aria-label="Unit"
        value={item.unit}
        onChange={(event) => onPatch({ unit: event.target.value })}
        placeholder="unit"
        className="w-[72px]"
      />
      <Input
        aria-label="Unit price"
        type="number"
        min="0"
        step="0.01"
        value={item.unit_price}
        onChange={(event) => onPatch({ unit_price: event.target.value })}
        className="w-[96px]"
      />
      {isRemovable && (
        <button
          type="button"
          onClick={onRemove}
          aria-label="Remove line item"
          className="mb-1.5 rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-destructive"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );
}

interface ChangeOrderLineItemsProps {
  items: ChangeOrderItem[];
  onPatchItem: (key: string, patch: Partial<ChangeOrderItem>) => void;
  onAddItem: () => void;
  onRemoveItem: (key: string) => void;
}

/** The priced rows. The last remaining row keeps no remove control — a change
 *  order with nothing on it is not a document worth saving. */
export function ChangeOrderLineItems({
  items,
  onPatchItem,
  onAddItem,
  onRemoveItem,
}: ChangeOrderLineItemsProps) {
  return (
    <Card>
      <CardContent className="space-y-2 pt-6">
        <Label>Line items</Label>
        {items.map((item) => (
          <ChangeOrderLineRow
            key={item.key}
            item={item}
            isRemovable={items.length > 1}
            onPatch={(patch) => onPatchItem(item.key, patch)}
            onRemove={() => onRemoveItem(item.key)}
          />
        ))}
        <Button type="button" variant="outline" size="sm" onClick={onAddItem}>
          <Plus className="h-3.5 w-3.5" />
          Add line item
        </Button>
      </CardContent>
    </Card>
  );
}
