"use client";

import { useState } from "react";
import { Building2, Loader2 } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useCompany, useUpdateCompany } from "@/lib/api/contracts";
import { usePermissions } from "@/lib/hooks/usePermissions";

/**
 * The company's own details — the ones printed on every quote, invoice and
 * contract a client receives.
 *
 * Nothing in the app could edit these before: registration captures a name and
 * the remaining columns were never written. Gated on company.settings.manage,
 * which the backend now enforces on PATCH /companies/{id} — that endpoint used
 * to accept any authenticated caller, so a worker could rename the company.
 *
 * License number is deliberately absent: it has its own section below, where the
 * contract merge field is explained. Two controls for one value is a bug waiting
 * to happen.
 */

interface CompanyProfileFormProps {
  companyId: string;
}

/** Trade types are a list on the wire and a comma-separated field on screen. */
function parseTradeTypes(value: string): string[] | null {
  const trades = value
    .split(",")
    .map((trade) => trade.trim())
    .filter((trade) => trade.length > 0);
  return trades.length > 0 ? trades : null;
}

function emptyToNull(value: string): string | null {
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

export function CompanyProfileForm({ companyId }: CompanyProfileFormProps) {
  const { can, isLoading: permissionsLoading } = usePermissions();
  const { data: company, isLoading: companyLoading } = useCompany(companyId);
  const updateCompany = useUpdateCompany(companyId);

  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [phone, setPhone] = useState("");
  const [businessNumber, setBusinessNumber] = useState("");
  const [tradeTypes, setTradeTypes] = useState("");
  const [logoUrl, setLogoUrl] = useState("");

  // Render-time sync, matching the licence section: seed the fields once the
  // company loads rather than setting state from an effect.
  const [syncedId, setSyncedId] = useState<string | null>(null);
  if (company && company.id !== syncedId) {
    setSyncedId(company.id);
    setName(company.name ?? "");
    setAddress(company.address ?? "");
    setPhone(company.phone ?? "");
    setBusinessNumber(company.business_number ?? "");
    setTradeTypes((company.trade_types ?? []).join(", "));
    setLogoUrl(company.logo_url ?? "");
  }

  if (permissionsLoading) {
    return <div className="h-64 animate-pulse rounded-xl bg-muted" />;
  }

  if (!can("company.settings.manage")) {
    return null;
  }

  const nameIsEmpty = name.trim() === "";

  function handleSave() {
    if (updateCompany.isPending || nameIsEmpty) return;
    updateCompany.mutate(
      {
        name: name.trim(),
        address: emptyToNull(address),
        phone: emptyToNull(phone),
        business_number: emptyToNull(businessNumber),
        trade_types: parseTradeTypes(tradeTypes),
        logo_url: emptyToNull(logoUrl),
      },
      {
        onSuccess: () => toast.success("Company profile saved."),
        onError: () =>
          toast.error("Could not save the company profile. Try again.", {
            duration: Infinity,
          }),
      }
    );
  }

  return (
    <section className="rounded-xl bg-card px-5 py-5 ring-1 ring-foreground/10">
      <p className="eyebrow text-brand">Profile</p>
      <h2 className="flex items-center gap-2 font-display text-lg font-bold tracking-tight text-foreground">
        <Building2 className="h-5 w-5" />
        Company details
      </h2>
      <p className="mt-1 text-sm text-muted-foreground">
        These appear on the quotes, invoices and contracts your clients receive.
      </p>

      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5 sm:col-span-2">
          <Label htmlFor="company-name">Company name</Label>
          <Input
            id="company-name"
            value={name}
            onChange={(event) => setName(event.target.value)}
            disabled={companyLoading}
            aria-invalid={nameIsEmpty}
          />
          {nameIsEmpty ? (
            <p role="alert" className="text-xs text-red-600">
              A company name is required.
            </p>
          ) : null}
        </div>

        <div className="space-y-1.5 sm:col-span-2">
          <Label htmlFor="company-address">Address</Label>
          <Input
            id="company-address"
            value={address}
            onChange={(event) => setAddress(event.target.value)}
            placeholder="12 Elm St, Springfield"
            disabled={companyLoading}
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="company-phone">Phone</Label>
          <Input
            id="company-phone"
            value={phone}
            onChange={(event) => setPhone(event.target.value)}
            placeholder="555-0101"
            disabled={companyLoading}
          />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="company-business-number">Business number</Label>
          <Input
            id="company-business-number"
            value={businessNumber}
            onChange={(event) => setBusinessNumber(event.target.value)}
            placeholder="BN-4421"
            disabled={companyLoading}
          />
        </div>

        <div className="space-y-1.5 sm:col-span-2">
          <Label htmlFor="company-trades">Trades</Label>
          <Input
            id="company-trades"
            value={tradeTypes}
            onChange={(event) => setTradeTypes(event.target.value)}
            placeholder="Plumbing, Electrical, Framing"
            disabled={companyLoading}
          />
          <p className="text-xs text-muted-foreground">Separate trades with commas.</p>
        </div>

        <div className="space-y-1.5 sm:col-span-2">
          <Label htmlFor="company-logo">Logo URL</Label>
          <Input
            id="company-logo"
            value={logoUrl}
            onChange={(event) => setLogoUrl(event.target.value)}
            placeholder="https://example.com/logo.png"
            disabled={companyLoading}
          />
        </div>
      </div>

      <div className="mt-4">
        <Button
          variant="brand"
          onClick={handleSave}
          disabled={updateCompany.isPending || companyLoading || nameIsEmpty}
        >
          {updateCompany.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
          Save profile
        </Button>
      </div>
    </section>
  );
}
