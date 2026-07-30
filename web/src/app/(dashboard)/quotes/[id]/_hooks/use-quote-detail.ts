import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiGet, apiPost, ApiError } from "@/lib/api-client";
import { downloadFileFromApi } from "@/lib/download-file";
import type { Quote, Job, Invoice } from "@/types/api";
import { useAppDispatch } from "@/store/hooks";
import { setPageTitle } from "@/store/slices/ui-slice";

const SEND_FAILED_PREFIX = "Failed to send quote.";

export function useQuoteDetail(id: string) {
  const router = useRouter();
  const dispatch = useAppDispatch();
  const queryClient = useQueryClient();

  const [isPdfDownloading, setPdfDownloading] = useState(false);
  const quoteRef = `QT-${id.slice(0, 6).toUpperCase()}`;

  // Queries -----------------------------------------------------------------

  // "new" is the create sentinel used by /quotes/new/edit — never fetch it as a
  // real quote (the backend rejects a non-UUID id with 422).
  const isNew = id === "new";

  const { data: quote, isLoading, isError } = useQuery<Quote>({
    queryKey: ["quote", id],
    queryFn: () => apiGet<Quote>(`/api/v1/quotes/${id}`),
    enabled: !isNew,
  });

  const { data: job } = useQuery<Job>({
    queryKey: ["job", quote?.job_id],
    queryFn: () => apiGet<Job>(`/api/v1/jobs/${quote!.job_id}`),
    enabled: !!quote?.job_id,
  });

  const { data: linkedInvoice } = useQuery<Invoice | null>({
    queryKey: ["invoice-for-job", quote?.job_id],
    queryFn: () =>
      apiGet<Invoice>(`/api/v1/invoices/for-job/${quote!.job_id}`, {
        silentStatuses: [404],
      }).catch(() => null),
    enabled: !!quote?.job_id && quote?.status === "approved",
  });

  // Side effects ------------------------------------------------------------

  useEffect(() => {
    if (quote) dispatch(setPageTitle(`Quote #${quoteRef}`));
    return () => {
      dispatch(setPageTitle(null));
    };
  }, [quote, quoteRef, dispatch]);

  useEffect(() => {
    if (isError) {
      toast.error(
        "Failed to load quote. Check your connection and try again.",
        { duration: Infinity }
      );
    }
  }, [isError]);

  // Mutations ---------------------------------------------------------------

  const sendMutation = useMutation<Quote, Error, void>({
    mutationFn: () => apiPost<Quote>(`/api/v1/quotes/${id}/send`, {}),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["quote", id] });
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success(`Quote sent to ${job?.client_name ?? "client"}`);
    },
    // A 409 here means the server's D-07 unreviewed-AI-lines check fired on a
    // stale client — its detail is user-facing copy the backend owns and
    // 37-UI-SPEC locks, so it is surfaced verbatim rather than swallowed
    // behind the generic message.
    onError: (err) =>
      toast.error(
        err instanceof ApiError ? err.detail : `${SEND_FAILED_PREFIX} Try again.`,
        { duration: Infinity }
      ),
  });

  const extendMutation = useMutation<Quote, Error, string>({
    mutationFn: (newDate) =>
      apiPost<Quote>(`/api/v1/quotes/${id}/extend`, { new_expiry_date: newDate }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["quote", id] });
      queryClient.invalidateQueries({ queryKey: ["quotes"] });
      toast.success("Expiry date extended successfully.");
    },
    onError: () =>
      toast.error("Failed to extend expiry. Try again.", {
        duration: Infinity,
      }),
  });

  const generateInvoiceMutation = useMutation<Invoice, Error, void>({
    mutationFn: () =>
      apiPost<Invoice>(`/api/v1/invoices/generate/${quote!.job_id}`, {}),
    onSuccess: (invoice) => {
      toast.success(`Invoice #${invoice.invoice_number} generated`);
      router.push(`/invoices/${invoice.id}`);
    },
    onError: () =>
      toast.error("Failed to generate invoice. Try again.", {
        duration: Infinity,
      }),
  });

  // Actions -----------------------------------------------------------------

  async function downloadPdf() {
    if (isPdfDownloading) return;
    setPdfDownloading(true);
    const toastId = toast.loading("Downloading PDF...");
    try {
      await downloadFileFromApi(`/api/v1/quotes/${id}/pdf`, `quote-${id}.pdf`);
      toast.dismiss(toastId);
    } catch {
      toast.dismiss(toastId);
      toast.error("PDF download failed. Try again.", { duration: Infinity });
    } finally {
      setPdfDownloading(false);
    }
  }

  return {
    quote,
    job,
    linkedInvoice,
    isLoading,
    isError,
    quoteRef,
    isPdfDownloading,
    isSending: sendMutation.isPending,
    isExtending: extendMutation.isPending,
    isGeneratingInvoice: generateInvoiceMutation.isPending,
    sendQuote: () => sendMutation.mutate(),
    extendExpiry: (date: string) => extendMutation.mutate(date),
    generateInvoice: () => generateInvoiceMutation.mutate(),
    downloadPdf,
    goToEdit: () => router.push(`/quotes/${id}/edit`),
    goToRevise: () => router.push(`/quotes/${id}/edit?revise=true`),
  };
}
