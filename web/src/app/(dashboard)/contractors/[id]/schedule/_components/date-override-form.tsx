import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  formatOverrideDate,
  HOUR_OPTIONS,
  type CustomBlock,
} from "../_lib/schedule-overrides";

function HourSelect({
  value,
  placeholder,
  onChange,
}: {
  value: string;
  placeholder: string;
  onChange: (value: string) => void;
}) {
  return (
    <Select<string>
      value={value}
      onValueChange={(v) => v != null && onChange(v)}
    >
      <SelectTrigger className="w-28">
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        {HOUR_OPTIONS.map((h) => (
          <SelectItem key={h} value={h}>
            {h}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

interface DateOverrideFormProps {
  selectedDate: Date;
  isUnavailable: boolean;
  onIsUnavailableChange: (value: boolean) => void;
  customBlocks: CustomBlock[];
  onAddBlock: () => void;
  onUpdateBlock: (index: number, field: keyof CustomBlock, value: string) => void;
  onRemoveBlock: (index: number) => void;
  canRemoveOverride: boolean;
  isSaving: boolean;
  onSave: () => void;
  onRequestRemove: () => void;
}

export function DateOverrideForm({
  selectedDate,
  isUnavailable,
  onIsUnavailableChange,
  customBlocks,
  onAddBlock,
  onUpdateBlock,
  onRemoveBlock,
  canRemoveOverride,
  isSaving,
  onSave,
  onRequestRemove,
}: DateOverrideFormProps) {
  return (
    <div className="border rounded-lg p-4 space-y-4">
      <p className="text-sm font-medium text-gray-900">
        Override for{" "}
        <span className="font-semibold">{formatOverrideDate(selectedDate)}</span>
      </p>

      {/* Unavailable all day vs custom hours */}
      <div className="flex gap-4">
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="radio"
            name="override-type"
            checked={isUnavailable}
            onChange={() => onIsUnavailableChange(true)}
            className="accent-[#f5a623]"
          />
          <span className="text-sm">Unavailable all day</span>
        </label>
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="radio"
            name="override-type"
            checked={!isUnavailable}
            onChange={() => onIsUnavailableChange(false)}
            className="accent-[#f5a623]"
          />
          <span className="text-sm">Custom hours</span>
        </label>
      </div>

      {!isUnavailable && (
        <div className="space-y-3">
          {customBlocks.map((block, index) => (
            <div key={index} className="flex items-center gap-3">
              <HourSelect
                value={block.startHour}
                placeholder="Start"
                onChange={(v) => onUpdateBlock(index, "startHour", v)}
              />
              <span className="text-sm text-muted-foreground">to</span>
              <HourSelect
                value={block.endHour}
                placeholder="End"
                onChange={(v) => onUpdateBlock(index, "endHour", v)}
              />
              {customBlocks.length > 1 && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => onRemoveBlock(index)}
                  className="text-destructive hover:text-destructive"
                >
                  Remove
                </Button>
              )}
            </div>
          ))}
          <Button variant="outline" size="sm" onClick={onAddBlock}>
            Add block
          </Button>
        </div>
      )}

      <div className="flex gap-3 pt-2">
        <Button onClick={onSave} disabled={isSaving}>
          Save Override
        </Button>
        {canRemoveOverride && (
          <Button
            variant="destructive"
            onClick={onRequestRemove}
            disabled={isSaving}
          >
            Remove Override
          </Button>
        )}
      </div>
    </div>
  );
}
