"use client";

import { useState } from "react";
import { AlertTriangle, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import {
  useContractTemplate,
  useUpdateContractTemplate,
} from "@/lib/api/contracts";

// The placeholders the backend resolves at contract-generation time. Shown so
// counsel/staff know exactly what will merge into a sent contract.
const MERGE_FIELDS: { token: string; description: string }[] = [
  { token: "{{company_name}}", description: "Your company's legal name" },
  { token: "{{company_address}}", description: "Company mailing address" },
  { token: "{{company_license_number}}", description: "CSLB license number" },
  { token: "{{company_phone}}", description: "Company phone" },
  { token: "{{client_name}}", description: "Client's full name" },
  { token: "{{client_address}}", description: "Client / job-site address" },
  { token: "{{client_email}}", description: "Client's email" },
  { token: "{{project_description}}", description: "Scope of the work" },
  { token: "{{quote_number}}", description: "Source quote reference" },
  { token: "{{quote_total}}", description: "Total contract price" },
  { token: "{{payment_schedule}}", description: "Schedule of payments" },
  { token: "{{today}}", description: "Date the contract is generated" },
  {
    token: "{{validity_statement}}",
    description: "Quote validity notice",
  },
];

export function ContractTermsEditor() {
  const { data: template, isLoading, isError } = useContractTemplate();
  const updateTemplate = useUpdateContractTemplate();

  const [body, setBody] = useState("");
  // Render-time sync (not an effect): seed the editor once per loaded template.
  const [syncedTemplateId, setSyncedTemplateId] = useState<string | null>(null);
  if (template && template.id !== syncedTemplateId) {
    setSyncedTemplateId(template.id);
    setBody(template.body);
  }

  const isDirty = template ? body !== template.body : false;

  function handleSave() {
    if (!isDirty || updateTemplate.isPending) return;
    updateTemplate.mutate(
      { body },
      {
        onSuccess: () => toast.success("Contract terms saved."),
        onError: () =>
          toast.error("Could not save the terms. Try again.", {
            duration: Infinity,
          }),
      }
    );
  }

  return (
    <section className="rounded-xl bg-card ring-1 ring-foreground/10">
      {/* Persistent attorney-review banner — the legal guardrail for this feature */}
      <div className="flex items-start gap-3 border-b-2 border-brand bg-brand/15 px-5 py-4">
        <AlertTriangle className="mt-0.5 h-5 w-5 flex-shrink-0 text-brand-foreground" />
        <div className="min-w-0">
          <p className="font-display text-sm font-bold text-foreground">
            Attorney review required
          </p>
          <p className="mt-0.5 text-sm text-foreground/80">
            This template ships as placeholder legal text structured around
            California statute. It is <strong>not legal advice</strong>. Have a
            licensed attorney review and finalize it before sending contracts to
            clients.
          </p>
        </div>
      </div>

      <div className="space-y-4 px-5 py-5">
        <div>
          <p className="eyebrow text-brand">Contract terms</p>
          <h2 className="font-display text-lg font-bold tracking-tight text-foreground">
            Terms template
          </h2>
          <p className="mt-1 text-sm text-muted-foreground">
            The body that merges into every contract you generate. Edits never
            change contracts already sent — each freezes its terms at generation.
          </p>
        </div>

        {isLoading ? (
          <div className="h-72 animate-pulse rounded-lg bg-muted" />
        ) : isError ? (
          <p className="rounded-lg border border-destructive/30 bg-destructive/10 px-4 py-3 text-sm text-destructive">
            Could not load the terms template. Refresh to try again.
          </p>
        ) : (
          <>
            <Textarea
              value={body}
              onChange={(event) => setBody(event.target.value)}
              spellCheck={false}
              rows={20}
              className="min-h-[24rem] font-mono text-[0.8rem] leading-relaxed"
              aria-label="Contract terms template body"
            />

            <div className="rounded-lg border border-border bg-secondary/40 px-4 py-3">
              <p className="eyebrow text-muted-foreground">Merge fields</p>
              <p className="mt-1 text-xs text-muted-foreground">
                Type any of these placeholders — they resolve to real values when
                a contract is generated.
              </p>
              <dl className="mt-3 grid grid-cols-1 gap-x-6 gap-y-1.5 sm:grid-cols-2">
                {MERGE_FIELDS.map(({ token, description }) => (
                  <div
                    key={token}
                    className="flex items-baseline justify-between gap-3"
                  >
                    <dt>
                      <code className="num rounded bg-background px-1.5 py-0.5 text-[0.7rem] text-foreground ring-1 ring-foreground/10">
                        {token}
                      </code>
                    </dt>
                    <dd className="truncate text-right text-xs text-muted-foreground">
                      {description}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>

            <div className="flex items-center justify-end gap-3">
              {isDirty && (
                <span className="text-xs text-muted-foreground">
                  Unsaved changes
                </span>
              )}
              <Button
                variant="brand"
                onClick={handleSave}
                disabled={!isDirty || updateTemplate.isPending}
              >
                {updateTemplate.isPending && (
                  <Loader2 className="h-4 w-4 animate-spin" />
                )}
                Save terms
              </Button>
            </div>
          </>
        )}
      </div>
    </section>
  );
}
