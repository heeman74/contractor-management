import { Controller, type UseFormReturn } from "react-hook-form";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { QuoteFormValues } from "../_lib/quote-form";

interface QuoteSettingsCardProps {
  form: UseFormReturn<QuoteFormValues>;
}

export function QuoteSettingsCard({ form }: QuoteSettingsCardProps) {
  const {
    control,
    register,
    watch,
    formState: { errors },
  } = form;

  const discountType = watch("discount_type");
  const todayIso = new Date().toISOString().split("T")[0];

  return (
    <Card>
      <CardHeader>
        <CardTitle>Quote Settings</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
          {/* Tax rate */}
          <div className="space-y-1">
            <label className="text-xs font-semibold text-gray-700">Tax Rate</label>
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
              <p className="text-xs text-red-500">{errors.tax_rate.message}</p>
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
                  className="h-8 rounded-lg border border-input bg-transparent px-2.5 py-1 text-sm focus:outline-none focus:ring-2 focus:ring-ring w-full max-w-[200px]"
                  value={field.value ?? ""}
                  onChange={(e) => field.onChange(e.target.value || null)}
                  min={todayIso}
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
                  onValueChange={(v) => field.onChange(v === "none" ? null : v)}
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
          <label className="text-xs font-semibold text-gray-700">Admin Notes</label>
          <Controller
            control={control}
            name="admin_notes"
            render={({ field }) => (
              <Textarea
                placeholder="Internal notes (not visible to client)..."
                className="resize-none"
                rows={3}
                value={field.value ?? ""}
                onChange={(e) => field.onChange(e.target.value || null)}
              />
            )}
          />
        </div>
      </CardContent>
    </Card>
  );
}
