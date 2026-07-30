import { useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { toast } from "sonner";
import { apiGet, apiPost, apiPatch, ApiError } from "@/lib/api-client";
import type { Quote, QuoteTemplate } from "@/types/api";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";
import {
  DEFAULT_FORM_VALUES,
  buildQuotePayload,
  mapQuoteToFormValues,
  quoteFormSchema,
  type QuoteFormValues,
} from "../_lib/quote-form";

function mutationErrorMessage(action: string, err: Error): string {
  const detail = err instanceof ApiError ? err.detail : "Try again.";
  return `${action} ${detail}`;
}

function parseTemplateLineItems(template: QuoteTemplate) {
  const parsed = JSON.parse(template.line_items_json) as Array<{
    item_type: "labor" | "material";
    description: string;
    quantity: string | number;
    unit: string;
    unit_price: string | number;
    sort_order?: number;
  }>;
  return parsed.map((item, index) => ({
    item_type: item.item_type,
    description: item.description,
    quantity: String(item.quantity),
    unit: item.unit,
    unit_price: String(item.unit_price),
    sort_order: item.sort_order ?? index,
  }));
}

export function useQuoteEditor(id: string) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  const isNew = id === "new";
  const isRevise = searchParams.get("revise") === "true";
  const jobIdParam = searchParams.get("job_id");

  const [pendingTemplate, setPendingTemplate] = useState<QuoteTemplate | null>(
    null
  );

  // Queries -----------------------------------------------------------------

  const { data: existingQuote, isLoading: quoteLoading } = useQuery<Quote>({
    queryKey: ["quote", id],
    queryFn: () => apiGet<Quote>(`/api/v1/quotes/${id}`),
    enabled: !isNew,
  });

  const { data: templates = [] } = useQuery<QuoteTemplate[]>({
    queryKey: ["quote-templates"],
    queryFn: () => apiGet<QuoteTemplate[]>("/api/v1/quotes/templates"),
  });

  // Form --------------------------------------------------------------------

  const form = useForm<QuoteFormValues>({
    resolver: zodResolver(quoteFormSchema),
    defaultValues: DEFAULT_FORM_VALUES,
  });
  const { reset, getValues } = form;

  useEffect(() => {
    if (existingQuote) {
      reset(mapQuoteToFormValues(existingQuote));
    }
  }, [existingQuote, reset]);

  // Page title --------------------------------------------------------------

  const pageTitle = isNew
    ? "New Quote"
    : isRevise && existingQuote
      ? `Revise Quote — v${existingQuote.revision_number + 1}`
      : existingQuote
        ? `Edit Quote — v${existingQuote.revision_number}`
        : "Edit Quote";

  useEffect(() => {
    dispatch(setPageTitle(pageTitle));
    return () => {
      dispatch(setPageTitle(null));
    };
  }, [pageTitle, dispatch]);

  const revisionNumber = isRevise
    ? (existingQuote?.revision_number ?? 1) + 1
    : (existingQuote?.revision_number ?? 1);

  // Templates ---------------------------------------------------------------

  function applyTemplate(template: QuoteTemplate) {
    try {
      reset({
        ...getValues(),
        line_items: parseTemplateLineItems(template),
        tax_rate: template.tax_rate,
      });
    } catch {
      toast.error("Failed to load template. Invalid template data.", {
        duration: Infinity,
      });
    }
  }

  function selectTemplate(templateId: string) {
    const template = templates.find((t) => t.id === templateId);
    if (!template) return;

    const items = getValues("line_items");
    const hasContent = items.length > 1 || Boolean(items[0]?.description);
    if (hasContent) {
      setPendingTemplate(template);
    } else {
      applyTemplate(template);
    }
  }

  function confirmPendingTemplate() {
    if (pendingTemplate) applyTemplate(pendingTemplate);
    setPendingTemplate(null);
  }

  // Mutations ---------------------------------------------------------------

  const jobId = isNew ? (jobIdParam ?? "") : (existingQuote?.job_id ?? "");

  const createMutation = useMutation({
    mutationFn: (data: QuoteFormValues) =>
      apiPost<Quote>("/api/v1/quotes/", {
        job_id: jobId,
        ...buildQuotePayload(data),
      }),
    onSuccess: (quote) => {
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Quote saved as draft");
      router.push(`/quotes/${quote.id}`);
    },
    onError: (err: Error) =>
      toast.error(mutationErrorMessage("Failed to save quote.", err), {
        duration: Infinity,
      }),
  });

  const updateMutation = useMutation({
    mutationFn: (data: QuoteFormValues) =>
      apiPatch<Quote>(`/api/v1/quotes/${id}`, buildQuotePayload(data)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["quote", id] });
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Quote updated");
      router.push(`/quotes/${id}`);
    },
    onError: (err: Error) =>
      toast.error(mutationErrorMessage("Failed to update quote.", err), {
        duration: Infinity,
      }),
  });

  const reviseMutation = useMutation({
    mutationFn: (data: QuoteFormValues) =>
      apiPost<Quote>(`/api/v1/quotes/${id}/revise`, buildQuotePayload(data)),
    onSuccess: (newQuote) => {
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Revision created");
      router.push(`/quotes/${newQuote.id}`);
    },
    onError: (err: Error) =>
      toast.error(mutationErrorMessage("Failed to create revision.", err), {
        duration: Infinity,
      }),
  });

  function submit(data: QuoteFormValues) {
    if (isRevise) reviseMutation.mutate(data);
    else if (isNew) createMutation.mutate(data);
    else updateMutation.mutate(data);
  }

  const isMutating =
    createMutation.isPending ||
    updateMutation.isPending ||
    reviseMutation.isPending;

  function cancel() {
    if (isNew) router.back();
    else router.push(`/quotes/${id}`);
  }

  return {
    form,
    templates,
    isNew,
    quoteLoading,
    existingQuote,
    pageTitle,
    revisionNumber,
    pendingTemplate,
    selectTemplate,
    confirmPendingTemplate,
    cancelPendingTemplate: () => setPendingTemplate(null),
    submit,
    cancel,
    isMutating,
  };
}
