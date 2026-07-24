"use client";

import { useEffect, useState } from "react";
import { CheckCircle2 } from "lucide-react";

interface EmbeddedSignerProps {
  signUrl: string;
  onSigned?: () => void;
}

/**
 * Hosts the provider's embedded signing ceremony.
 *
 * Implementation note: this uses a plain <iframe> of the provider's `sign_url`
 * rather than the provider's CDN JS client, to avoid a new dependency and any
 * Content-Security-Policy friction. All provider-specific knowledge (the signed
 * event names, the frame origin) is contained in THIS file, so swapping Dropbox
 * Sign for DocuSign later only touches this component.
 *
 * Dropbox Sign's embedded iframe still posts window messages to its parent even
 * when hosted directly; we listen for its "signed" events to flip to a success
 * state. NEXT_PUBLIC_DROPBOX_SIGN_CLIENT_ID is read only if a future switch to
 * the JS client is needed — the iframe path does not require it.
 */

// Provider-specific: Dropbox Sign (HelloSign) embedded message signatures.
const PROVIDER_MESSAGE_KEY = "hellosign";
const SIGNED_EVENT_TYPES = [
  "signature_request_signed",
  "signature_request_all_signed",
];

function isSignedMessage(data: unknown): boolean {
  if (typeof data === "string") {
    return SIGNED_EVENT_TYPES.some((eventType) => data.includes(eventType));
  }
  if (data && typeof data === "object") {
    const record = data as Record<string, unknown>;
    const type = typeof record.type === "string" ? record.type : "";
    const payload =
      record.payload && typeof record.payload === "object"
        ? (record.payload as Record<string, unknown>)
        : undefined;
    const payloadType =
      payload && typeof payload.type === "string" ? payload.type : "";
    if (type === PROVIDER_MESSAGE_KEY && SIGNED_EVENT_TYPES.includes(payloadType)) {
      return true;
    }
    return SIGNED_EVENT_TYPES.includes(type);
  }
  return false;
}

export function EmbeddedSigner({ signUrl, onSigned }: EmbeddedSignerProps) {
  const [signed, setSigned] = useState(false);

  useEffect(() => {
    function handleMessage(event: MessageEvent) {
      if (!isSignedMessage(event.data)) return;
      setSigned(true);
      onSigned?.();
    }
    window.addEventListener("message", handleMessage);
    return () => window.removeEventListener("message", handleMessage);
  }, [onSigned]);

  if (signed) {
    return (
      <div className="flex flex-col items-center gap-3 rounded-xl border border-brand/40 bg-brand/10 px-6 py-10 text-center">
        <CheckCircle2 className="h-10 w-10 text-brand-foreground" />
        <div>
          <p className="font-display text-lg font-bold text-foreground">
            Signature complete
          </p>
          <p className="mt-1 text-sm text-muted-foreground">
            Thanks — your signed contract has been sent to your contractor. You
            can close this page.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="overflow-hidden rounded-xl border border-border bg-white">
      <iframe
        src={signUrl}
        title="Sign your contract"
        className="h-[70vh] min-h-[520px] w-full border-0"
        allow="camera; microphone"
      />
    </div>
  );
}
