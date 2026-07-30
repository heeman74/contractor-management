import type { QuoteLineItem } from "@/types/api";

/** Every line item the AI seeded, regardless of its current review state. */
export function aiLineCount(lineItems: QuoteLineItem[]): number {
  return lineItems.filter((item) => item.ai_origin).length;
}

/** AI-seeded lines still awaiting an Accept or an edit. */
export function unreviewedAiLineCount(lineItems: QuoteLineItem[]): number {
  return lineItems.filter(
    (item) => item.ai_origin && item.review_state === "unreviewed"
  ).length;
}

export const UNREVIEWED_BANNER_BODY =
  "Accept each line as-is or edit it, then save the draft. A quote can't be sent while any suggested line is unreviewed.";

const UNREVIEWED_BANNER_HEADING_SINGULAR = "1 AI-suggested line still needs review";
const UNREVIEWED_BANNER_HEADING_PLURAL = "AI-suggested lines still need review";

export function unreviewedBannerCopy(count: number): {
  heading: string;
  body: string;
} {
  const heading =
    count === 1
      ? UNREVIEWED_BANNER_HEADING_SINGULAR
      : `${count} ${UNREVIEWED_BANNER_HEADING_PLURAL}`;
  return { heading, body: UNREVIEWED_BANNER_BODY };
}

const SEND_BLOCKED_HEADING = "Review the AI-suggested line items before sending";
const SEND_BLOCKED_BODY_TAIL =
  "The check runs on the server, so a quote can't be sent from any screen until every suggestion is reviewed.";

export function sendBlockedCopy(count: number): {
  heading: string;
  body: string;
} {
  const lineWord = count === 1 ? "line hasn't" : "lines haven't";
  return {
    heading: SEND_BLOCKED_HEADING,
    body: `${count} suggested ${lineWord} been accepted or edited yet. ${SEND_BLOCKED_BODY_TAIL}`,
  };
}

/** The AI provenance line, rendered last in the caption stack on BOTH the editor
 *  (37-05) and the read-only quote detail card (37-06). It lives here because
 *  those two plans run in the same wave and neither may own a string the other
 *  imports. */
export const AI_DISCLOSURE_NOTE =
  "AI-suggested from your own completed work — every figure is from your recorded history, never an AI estimate.";
