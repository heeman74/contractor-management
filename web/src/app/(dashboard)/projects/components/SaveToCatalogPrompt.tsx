"use client";

import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";

interface SaveToCatalogPromptProps {
  tradeName: string;
  onSave: () => void;
  onUseOnce: () => void;
  isSaving: boolean;
}

export function SaveToCatalogPrompt({
  tradeName,
  onSave,
  onUseOnce,
  isSaving,
}: SaveToCatalogPromptProps) {
  return (
    <Alert>
      <AlertDescription className="flex flex-col gap-2">
        <p className="text-sm">
          &quot;{tradeName}&quot; is not in your trade catalog. Save it for future projects?
        </p>
        <div className="flex items-center gap-2">
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={onSave}
            disabled={isSaving}
            data-testid="save-to-catalog-button"
          >
            Save to Catalog
          </Button>
          <Button
            type="button"
            variant="link"
            size="sm"
            onClick={onUseOnce}
            data-testid="use-once-button"
          >
            Use Once
          </Button>
        </div>
      </AlertDescription>
    </Alert>
  );
}
