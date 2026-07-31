"use client";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { ChangeOrderForm, ChangeOrderTarget } from "../_lib/change-order";

const REASON_PLACEHOLDER = "e.g. Rotted subfloor discovered under the existing tile";

interface ChangeOrderContextFieldsProps {
  form: ChangeOrderForm;
  onPatch: (patch: Partial<ChangeOrderForm>) => void;
}

/** Why the change is needed and what approving it does — the three fields that
 *  distinguish a change order from an ordinary quote. */
export function ChangeOrderContextFields({
  form,
  onPatch,
}: ChangeOrderContextFieldsProps) {
  return (
    <>
      <div>
        <Label htmlFor="co-reason">Reason for change</Label>
        <Textarea
          id="co-reason"
          value={form.reason}
          onChange={(event) => onPatch({ reason: event.target.value })}
          rows={3}
          placeholder={REASON_PLACEHOLDER}
          className="mt-1"
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <Label>Apply approved work to</Label>
          <Select
            value={form.co_target}
            onValueChange={(value) => {
              if (value) onPatch({ co_target: value as ChangeOrderTarget });
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
            onChange={(event) => onPatch({ schedule_impact_days: event.target.value })}
            placeholder="0"
            className="mt-1"
          />
        </div>
      </div>
    </>
  );
}
