"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Plus, Check, ChevronsUpDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Alert, AlertDescription } from "@/components/ui/alert";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetFooter,
} from "@/components/ui/sheet";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { cn } from "@/lib/utils";
import {
  useTradeCatalog,
  useContractors,
  createTradeScope,
  createTradeCatalogEntry,
} from "@/lib/api/projects";
import type { TradeCatalogResponse } from "@/types/projects";

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
  const queryClient = useQueryClient();

  // Trade name combobox state
  const [comboOpen, setComboOpen] = useState(false);
  const [tradeSearch, setTradeSearch] = useState("");
  const [selectedCatalogId, setSelectedCatalogId] = useState<string | null>(null);
  const [tradeName, setTradeName] = useState("");
  const [tradeColor, setTradeColor] = useState("#6b7280");
  const [isAdHoc, setIsAdHoc] = useState(false);
  const [saveToCatalogDismissed, setSaveToCatalogDismissed] = useState(false);

  // Contractor state
  const [contractorId, setContractorId] = useState<string>("");

  const { data: catalog } = useTradeCatalog();
  const { data: contractors } = useContractors(selectedCatalogId ?? undefined);

  const filteredCatalog = catalog?.filter((entry) =>
    entry.name.toLowerCase().includes(tradeSearch.toLowerCase())
  ) ?? [];

  const showNewTradeOption =
    tradeSearch.trim().length > 0 &&
    !filteredCatalog.some(
      (e) => e.name.toLowerCase() === tradeSearch.toLowerCase()
    );

  const showSaveToCatalogPrompt = isAdHoc && !saveToCatalogDismissed && tradeName.trim().length > 0;

  // Specialty-sorted contractors
  const specialtyContractors = contractors?.filter((c) => c.has_specialty_match) ?? [];
  const otherContractors = contractors?.filter((c) => !c.has_specialty_match) ?? [];

  const saveCatalogMutation = useMutation({
    mutationFn: () =>
      createTradeCatalogEntry({ name: tradeName, color: tradeColor }),
    onSuccess: (newEntry: TradeCatalogResponse) => {
      setSelectedCatalogId(newEntry.id);
      setIsAdHoc(false);
      setSaveToCatalogDismissed(true);
      queryClient.invalidateQueries({ queryKey: ["trade-catalog"] });
      toast.success("Trade added to catalog.");
    },
    onError: () => {
      toast.error("Failed to save to catalog.");
    },
  });

  const createScopeMutation = useMutation({
    mutationFn: () =>
      createTradeScope({
        project_id: projectId,
        trade_catalog_id: selectedCatalogId ?? undefined,
        trade_name: tradeName,
        trade_color: tradeColor,
        contractor_id: contractorId || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["trade-scopes", projectId] });
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      toast.success("Trade scope added.");
      resetForm();
      onSuccess();
    },
    onError: () => {
      toast.error("Something went wrong. Please try again.");
    },
  });

  const resetForm = () => {
    setTradeSearch("");
    setSelectedCatalogId(null);
    setTradeName("");
    setTradeColor("#6b7280");
    setIsAdHoc(false);
    setSaveToCatalogDismissed(false);
    setContractorId("");
    setComboOpen(false);
  };

  const handleSelectCatalogEntry = (entry: TradeCatalogResponse) => {
    setSelectedCatalogId(entry.id);
    setTradeName(entry.name);
    setTradeColor(entry.color);
    setIsAdHoc(false);
    setSaveToCatalogDismissed(false);
    setTradeSearch(entry.name);
    setComboOpen(false);
  };

  const handleSelectNewTrade = () => {
    setSelectedCatalogId(null);
    setTradeName(tradeSearch.trim());
    setIsAdHoc(true);
    setSaveToCatalogDismissed(false);
    setComboOpen(false);
  };

  const handleSubmit = () => {
    if (!tradeName.trim()) {
      toast.error("Trade name is required.");
      return;
    }
    createScopeMutation.mutate();
  };

  return (
    <Sheet open={open} onOpenChange={(o) => { if (!o) resetForm(); onOpenChange(o); }}>
      <SheetContent side="right" className="w-full sm:max-w-md overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Add Trade Scope</SheetTitle>
        </SheetHeader>

        <div className="flex flex-col gap-5 px-4 py-4">
          {/* Trade Name Combobox */}
          <div className="flex flex-col gap-1.5">
            <Label>Trade Name *</Label>
            <Popover open={comboOpen} onOpenChange={setComboOpen}>
              <PopoverTrigger
                className="flex h-9 w-full items-center justify-between rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2"
                aria-label="Select trade name"
                data-testid="trade-name-combobox"
              >
                <span className={cn(!tradeName && "text-muted-foreground")}>
                  {tradeName || "Search or create trade..."}
                </span>
                <ChevronsUpDown className="ml-2 h-4 w-4 flex-shrink-0 text-gray-400" />
              </PopoverTrigger>
              <PopoverContent
                className="w-full min-w-[280px] p-0"
                align="start"
              >
                <div className="flex flex-col">
                  <input
                    className="w-full border-b border-input bg-transparent px-3 py-2 text-sm outline-none placeholder:text-muted-foreground"
                    placeholder="Search trades..."
                    value={tradeSearch}
                    onChange={(e) => setTradeSearch(e.target.value)}
                    autoFocus
                    data-testid="trade-search-input"
                  />
                  <div className="max-h-60 overflow-y-auto py-1">
                    {filteredCatalog.map((entry) => (
                      <button
                        key={entry.id}
                        type="button"
                        className="flex w-full cursor-pointer items-center gap-2 px-3 py-2 text-sm hover:bg-accent hover:text-accent-foreground"
                        onClick={() => handleSelectCatalogEntry(entry)}
                      >
                        <span
                          className="inline-block h-3 w-3 flex-shrink-0 rounded-full"
                          style={{ backgroundColor: entry.color || "#6b7280" }}
                        />
                        <span className="flex-1 text-left">{entry.name}</span>
                        {selectedCatalogId === entry.id && (
                          <Check className="h-3.5 w-3.5 text-indigo-600" />
                        )}
                      </button>
                    ))}
                    {showNewTradeOption && (
                      <button
                        type="button"
                        className="flex w-full cursor-pointer items-center gap-2 px-3 py-2 text-sm text-indigo-600 hover:bg-indigo-50"
                        onClick={handleSelectNewTrade}
                        data-testid="create-new-trade-option"
                      >
                        <Plus className="h-3.5 w-3.5" />
                        <span>Create new trade: &quot;{tradeSearch}&quot;</span>
                      </button>
                    )}
                    {filteredCatalog.length === 0 && !showNewTradeOption && (
                      <p className="px-3 py-2 text-sm text-gray-500">
                        No trades found. Type to create a new one.
                      </p>
                    )}
                  </div>
                </div>
              </PopoverContent>
            </Popover>
          </div>

          {/* Save to Catalog prompt (ad-hoc trades only) */}
          {showSaveToCatalogPrompt && (
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
                    onClick={() => saveCatalogMutation.mutate()}
                    disabled={saveCatalogMutation.isPending}
                    data-testid="save-to-catalog-button"
                  >
                    Save to Catalog
                  </Button>
                  <Button
                    type="button"
                    variant="link"
                    size="sm"
                    onClick={() => setSaveToCatalogDismissed(true)}
                    data-testid="use-once-button"
                  >
                    Use Once
                  </Button>
                </div>
              </AlertDescription>
            </Alert>
          )}

          {/* Contractor Select */}
          <div className="flex flex-col gap-1.5">
            <Label>Contractor (optional)</Label>
            <Select
              value={contractorId}
              onValueChange={(v) => setContractorId(v ?? "")}
            >
              <SelectTrigger className="w-full" data-testid="contractor-select">
                <SelectValue placeholder="Select contractor..." />
              </SelectTrigger>
              <SelectContent>
                {specialtyContractors.length > 0 && (
                  <>
                    {specialtyContractors.map((c) => (
                      <SelectItem key={c.id} value={c.id}>
                        {c.name}{" "}
                        <span className="text-xs text-indigo-500">
                          (Specialty match)
                        </span>
                      </SelectItem>
                    ))}
                    {otherContractors.length > 0 && (
                      <div className="my-1 border-t border-gray-100 px-2 py-1 text-xs font-medium text-gray-400">
                        Other Contractors
                      </div>
                    )}
                  </>
                )}
                {otherContractors.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
                {(!contractors || contractors.length === 0) && (
                  <div className="px-2 py-2 text-sm text-gray-500">
                    No contractors available.
                  </div>
                )}
              </SelectContent>
            </Select>
          </div>
        </div>

        <SheetFooter>
          <Button
            onClick={handleSubmit}
            disabled={createScopeMutation.isPending || !tradeName.trim()}
            className="w-full"
            data-testid="add-trade-scope-submit"
          >
            {createScopeMutation.isPending ? "Adding..." : "Add Trade Scope"}
          </Button>
        </SheetFooter>
      </SheetContent>
    </Sheet>
  );
}
