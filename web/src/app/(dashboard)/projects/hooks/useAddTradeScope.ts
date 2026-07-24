"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  useTradeCatalog,
  useContractors,
  createTradeScope,
  createTradeCatalogEntry,
} from "@/lib/api/projects";
import type { TradeCatalogResponse } from "@/types/projects";

const DEFAULT_TRADE_COLOR = "#6b7280";

interface UseAddTradeScopeParams {
  projectId: string;
  onSuccess: () => void;
}

export function useAddTradeScope({
  projectId,
  onSuccess,
}: UseAddTradeScopeParams) {
  const queryClient = useQueryClient();

  const [comboOpen, setComboOpen] = useState(false);
  const [tradeSearch, setTradeSearch] = useState("");
  const [selectedCatalogId, setSelectedCatalogId] = useState<string | null>(null);
  const [tradeName, setTradeName] = useState("");
  const [tradeColor, setTradeColor] = useState(DEFAULT_TRADE_COLOR);
  const [isAdHoc, setIsAdHoc] = useState(false);
  const [saveToCatalogDismissed, setSaveToCatalogDismissed] = useState(false);
  const [contractorId, setContractorId] = useState("");

  const { data: catalog } = useTradeCatalog();
  const { data: contractors } = useContractors(selectedCatalogId ?? undefined);

  const filteredCatalog =
    catalog?.filter((entry) =>
      entry.name.toLowerCase().includes(tradeSearch.toLowerCase())
    ) ?? [];

  const showNewTradeOption =
    tradeSearch.trim().length > 0 &&
    !filteredCatalog.some(
      (entry) => entry.name.toLowerCase() === tradeSearch.toLowerCase()
    );

  const showSaveToCatalogPrompt =
    isAdHoc && !saveToCatalogDismissed && tradeName.trim().length > 0;

  const specialtyContractors =
    contractors?.filter((c) => c.has_specialty_match) ?? [];
  const otherContractors =
    contractors?.filter((c) => !c.has_specialty_match) ?? [];

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

  function resetForm() {
    setTradeSearch("");
    setSelectedCatalogId(null);
    setTradeName("");
    setTradeColor(DEFAULT_TRADE_COLOR);
    setIsAdHoc(false);
    setSaveToCatalogDismissed(false);
    setContractorId("");
    setComboOpen(false);
  }

  function selectCatalogEntry(entry: TradeCatalogResponse) {
    setSelectedCatalogId(entry.id);
    setTradeName(entry.name);
    setTradeColor(entry.color);
    setIsAdHoc(false);
    setSaveToCatalogDismissed(false);
    setTradeSearch(entry.name);
    setComboOpen(false);
  }

  function selectNewTrade() {
    setSelectedCatalogId(null);
    setTradeName(tradeSearch.trim());
    setIsAdHoc(true);
    setSaveToCatalogDismissed(false);
    setComboOpen(false);
  }

  function submit() {
    if (!tradeName.trim()) {
      toast.error("Trade name is required.");
      return;
    }
    createScopeMutation.mutate();
  }

  return {
    comboOpen,
    setComboOpen,
    tradeSearch,
    setTradeSearch,
    selectedCatalogId,
    tradeName,
    contractorId,
    setContractorId,
    filteredCatalog,
    showNewTradeOption,
    showSaveToCatalogPrompt,
    specialtyContractors,
    otherContractors,
    hasContractors: Boolean(contractors && contractors.length > 0),
    isSavingCatalog: saveCatalogMutation.isPending,
    isCreatingScope: createScopeMutation.isPending,
    saveToCatalog: () => saveCatalogMutation.mutate(),
    dismissSaveToCatalog: () => setSaveToCatalogDismissed(true),
    resetForm,
    selectCatalogEntry,
    selectNewTrade,
    submit,
  };
}
