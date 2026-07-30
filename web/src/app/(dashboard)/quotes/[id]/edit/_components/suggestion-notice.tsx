import {
  suggestionRefusalCopy,
  type RefusalReason,
  type SuggestionRefusalContext,
} from "../_lib/suggestion-copy";

interface SuggestionNoticeProps {
  reason: RefusalReason;
  context: SuggestionRefusalContext;
}

/** The three refusal variants (cold start, trade unresolved, grounding drop)
 *  in one component; all copy comes from the `suggestion-copy` map so this
 *  component never carries a literal sentence. */
export function SuggestionNotice({ reason, context }: SuggestionNoticeProps) {
  const { heading, body } = suggestionRefusalCopy(reason, context);

  return (
    <div role="status" data-testid="suggestion-notice" className="rounded-lg bg-secondary p-4">
      <p className="text-sm font-medium">{heading}</p>
      <p className="text-sm">{body}</p>
    </div>
  );
}
