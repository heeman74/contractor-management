"use client";

import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetFooter,
} from "@/components/ui/sheet";
import { useAddTradeScope } from "../hooks/useAddTradeScope";
import { ContractorSelect } from "./ContractorSelect";
import { SaveToCatalogPrompt } from "./SaveToCatalogPrompt";
import { TradeNameCombobox } from "./TradeNameCombobox";

interface AddTradeScopeSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  projectId: string;
  onSuccess: () => void;
}

export function AddTradeScopeSheet({
  open,
  onOpenChange,
  projectId,
  onSuccess,
}: AddTradeScopeSheetProps) {
  const form = useAddTradeScope({ projectId, onSuccess });

  function handleSheetOpenChange(nextOpen: boolean) {
    if (!nextOpen) form.resetForm();
    onOpenChange(nextOpen);
  }

  return (
    <Sheet open={open} onOpenChange={handleSheetOpenChange}>
      <SheetContent side="right" className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Add Trade Scope</SheetTitle>
        </SheetHeader>

        <div className="flex flex-col gap-5 px-4 py-4">
          <TradeNameCombobox
            open={form.comboOpen}
            onOpenChange={form.setComboOpen}
            tradeName={form.tradeName}
            tradeSearch={form.tradeSearch}
            onTradeSearchChange={form.setTradeSearch}
            filteredCatalog={form.filteredCatalog}
            selectedCatalogId={form.selectedCatalogId}
            showNewTradeOption={form.showNewTradeOption}
            onSelectEntry={form.selectCatalogEntry}
            onSelectNewTrade={form.selectNewTrade}
          />

          {form.showSaveToCatalogPrompt && (
            <SaveToCatalogPrompt
              tradeName={form.tradeName}
              onSave={form.saveToCatalog}
              onUseOnce={form.dismissSaveToCatalog}
              isSaving={form.isSavingCatalog}
            />
          )}

          <ContractorSelect
            value={form.contractorId}
            onValueChange={form.setContractorId}
            specialtyContractors={form.specialtyContractors}
            otherContractors={form.otherContractors}
            hasContractors={form.hasContractors}
          />
        </div>

        <SheetFooter>
          <Button
            onClick={form.submit}
            disabled={form.isCreatingScope || !form.tradeName.trim()}
            className="w-full"
            data-testid="add-trade-scope-submit"
          >
            {form.isCreatingScope ? "Adding..." : "Add Trade Scope"}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}
