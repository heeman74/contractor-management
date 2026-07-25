"use client";

import { use } from "react";
import { useQuery } from "@tanstack/react-query";
import DOMPurify from "isomorphic-dompurify";
import { CheckCircle2, Download, FileWarning } from "lucide-react";
import { EmbeddedSigner } from "./_components/embedded-signer";
import type { PublicContractView } from "@/types/api";

async function fetchPublicContract(
  token: string
): Promise<PublicContractView> {
  const response = await fetch(
    `/api/public-contract/${encodeURIComponent(token)}`,
    { headers: { Accept: "application/json" } }
  );
  if (!response.ok) {
    throw new Error(`Contract unavailable (${response.status})`);
  }
  return (await response.json()) as PublicContractView;
}

function PageShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-background">
      {/* Ink header bar — the Job Ticket identity, no dashboard chrome */}
      <header className="relative overflow-hidden bg-sidebar text-white">
        <div className="blueprint-grid pointer-events-none absolute inset-0 text-white/60" />
        <div className="absolute inset-x-0 top-0 h-1 bg-brand" />
        <div className="relative mx-auto flex max-w-3xl items-center gap-2 px-5 py-4">
          <span className="inline-block h-3.5 w-3.5 rounded-[3px] bg-brand" />
          <span className="font-display text-sm font-bold tracking-tight">
            ContractorHub
          </span>
        </div>
      </header>
      <main className="mx-auto max-w-3xl px-5 py-8">{children}</main>
    </div>
  );
}

export default function SignContractPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = use(params);
  const { data, isLoading, isError, refetch } = useQuery<PublicContractView>({
    queryKey: ["public-contract", token],
    queryFn: () => fetchPublicContract(token),
    enabled: Boolean(token),
    retry: false,
  });

  if (isLoading) {
    return (
      <PageShell>
        <div className="h-96 animate-pulse rounded-xl bg-muted" />
      </PageShell>
    );
  }

  if (isError || !data) {
    return (
      <PageShell>
        <div className="flex flex-col items-center gap-3 rounded-xl bg-card px-6 py-14 text-center ring-1 ring-foreground/10">
          <FileWarning className="h-10 w-10 text-muted-foreground" />
          <p className="font-display text-lg font-bold text-foreground">
            This signing link is no longer valid
          </p>
          <p className="max-w-md text-sm text-muted-foreground">
            The link may have expired or already been used. Please contact your
            contractor to request a new one.
          </p>
        </div>
      </PageShell>
    );
  }

  const isSigned = data.status === "signed";

  return (
    <PageShell>
      <div className="space-y-6">
        {/* Contract header */}
        <div>
          <p className="eyebrow text-brand">Contract to sign</p>
          <h1 className="font-display text-2xl font-bold tracking-tight text-foreground">
            {data.company_name}
          </h1>
          {data.signer_name && (
            <p className="mt-1 text-sm text-muted-foreground">
              Prepared for {data.signer_name}
            </p>
          )}
        </div>

        {data.validity_statement && (
          <p className="rounded-lg border border-brand/40 bg-brand/10 px-4 py-3 text-sm text-foreground">
            {data.validity_statement}
          </p>
        )}

        {/* Terms — company-authored HTML, but a tenant admin (or a compromised
            tenant account) is still an untrusted source in a multi-tenant SaaS, and
            this HTML renders at the app's own origin. Sanitize with a strict allowlist
            (DOMPurify strips <script>, event handlers, <svg>/<iframe>, etc.) before
            rendering to prevent stored XSS against staff/signer viewers. */}
        <section className="rounded-xl bg-card px-6 py-6 ring-1 ring-foreground/10">
          <div
            className="prose prose-sm max-w-none text-sm leading-relaxed text-foreground [&_h1]:font-display [&_h2]:font-display [&_h3]:font-display"
            dangerouslySetInnerHTML={{
              __html: DOMPurify.sanitize(data.terms_snapshot, {
                USE_PROFILES: { html: true },
              }),
            }}
          />
        </section>

        {/* Signing area / signed state */}
        {isSigned ? (
          <div className="flex flex-col items-center gap-3 rounded-xl border border-brand/40 bg-brand/10 px-6 py-10 text-center">
            <CheckCircle2 className="h-10 w-10 text-brand-foreground" />
            <p className="font-display text-lg font-bold text-foreground">
              Signed
            </p>
            <p className="text-sm text-muted-foreground">
              This contract has been signed. Thank you.
            </p>
            {data.signed_pdf_url && (
              <a
                href={data.signed_pdf_url}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1.5 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
              >
                <Download className="h-4 w-4" />
                Download signed PDF
              </a>
            )}
          </div>
        ) : data.sign_url ? (
          <section className="space-y-3">
            <div>
              <p className="eyebrow text-brand">Sign</p>
              <h2 className="font-display text-lg font-bold tracking-tight text-foreground">
                Review and sign
              </h2>
            </div>
            <EmbeddedSigner
              signUrl={data.sign_url}
              onSigned={() => refetch()}
            />
          </section>
        ) : (
          <div className="rounded-xl bg-card px-6 py-10 text-center ring-1 ring-foreground/10">
            <p className="text-sm text-muted-foreground">
              This contract is not ready for signing yet. Please contact your
              contractor.
            </p>
          </div>
        )}
      </div>
    </PageShell>
  );
}
