import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { apiPost } from "@/lib/api-client";
import { SUGGEST_ERROR_MESSAGE, type RefusalReason } from "../_lib/suggestion-copy";

export interface QuoteSuggestionResult {
  refusalReason: RefusalReason | null;
  tradeName: string | null;
  comparableCount: number | null;
  requiredCount: number | null;
  suggestedLineCount: number;
}

interface QuoteSuggestionApiResponse {
  refusal_reason: RefusalReason | null;
  trade_name: string | null;
  comparable_count: number | null;
  required_count: number | null;
  suggested_line_count: number;
}

function toSuggestionResult(
  raw: QuoteSuggestionApiResponse
): QuoteSuggestionResult {
  return {
    refusalReason: raw.refusal_reason,
    tradeName: raw.trade_name,
    comparableCount: raw.comparable_count,
    requiredCount: raw.required_count,
    suggestedLineCount: raw.suggested_line_count,
  };
}

// The mapper lives inside the fetcher (the 36-02 precedent) so a hook test
// that mocks the HTTP layer (apiPost) exercises the path, the mapper and the
// request count in one go.
async function postSuggestLineItems(
  quoteId: string
): Promise<QuoteSuggestionResult> {
  const raw = await apiPost<QuoteSuggestionApiResponse>(
    `/api/v1/quotes/${quoteId}/suggest-line-items`,
    {}
  );
  return toSuggestionResult(raw);
}

/** One mutation, one refusal state, no optimistic rows. Accepting a line is
 *  form state (see the editor's AiLineSubRow) — this hook owns no accept
 *  logic. */
export function useQuoteSuggestions(quoteId: string) {
  const queryClient = useQueryClient();
  const [refusal, setRefusal] = useState<QuoteSuggestionResult | null>(null);

  const mutation = useMutation({
    mutationFn: () => postSuggestLineItems(quoteId),
    onSuccess: (result) => {
      setRefusal(result.refusalReason !== null ? result : null);
      // Invalidating here is safe ONLY because the trigger is disabled while
      // the form is dirty (state 4) — there is no unsaved row edit for the
      // shipped reset effect (use-quote-editor.ts) to discard when this
      // refetch lands and repopulates the form with the new lines.
      if (result.suggestedLineCount > 0) {
        queryClient.invalidateQueries({ queryKey: ["quote", quoteId] });
      }
    },
    onError: () => {
      setRefusal(null);
      toast.error(SUGGEST_ERROR_MESSAGE, { duration: Infinity });
    },
  });

  return {
    suggest: () => mutation.mutate(),
    isPending: mutation.isPending,
    refusal,
    clearRefusal: () => setRefusal(null),
  };
}
