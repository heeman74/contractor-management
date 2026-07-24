"use client";

import { useState } from "react";
import { Building2, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { usePermissions } from "@/lib/hooks/usePermissions";
import { useCompany, useUpdateCompany } from "@/lib/api/contracts";
import { ContractTermsEditor } from "./contract-terms-editor";

interface CompanySettingsFormProps {
  companyId: string;
}

export function CompanySettingsForm({ companyId }: CompanySettingsFormProps) {
  const { can, isLoading: permissionsLoading } = usePermissions();
  const { data: company, isLoading: companyLoading } = useCompany(companyId);
  const updateCompany = useUpdateCompany(companyId);

  const [licenseNumber, setLicenseNumber] = useState("");
  // Render-time sync: seed the field once the company loads (avoids setState in effect).
  const [syncedCompanyId, setSyncedCompanyId] = useState<string | null>(null);
  if (company && company.id !== syncedCompanyId) {
    setSyncedCompanyId(company.id);
    setLicenseNumber(company.license_number ?? "");
  }

  if (permissionsLoading) {
    return <div className="h-64 animate-pulse rounded-xl bg-muted" />;
  }

  if (!can("contracts.manage")) {
    return (
      <div className="rounded-xl border border-yellow-200 bg-yellow-50 px-6 py-12 text-center">
        <p className="text-sm font-medium text-yellow-700">
          You do not have permission to manage company contract settings.
        </p>
      </div>
    );
  }

  const currentLicense = company?.license_number ?? "";
  const isDirty = licenseNumber.trim() !== currentLicense;

  function handleSaveLicense() {
    if (!isDirty || updateCompany.isPending) return;
    const trimmed = licenseNumber.trim();
    updateCompany.mutate(
      { license_number: trimmed === "" ? null : trimmed },
      {
        onSuccess: () => toast.success("License number saved."),
        onError: () =>
          toast.error("Could not save the license number. Try again.", {
            duration: Infinity,
          }),
      }
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <p className="eyebrow text-brand">Company</p>
        <h1 className="flex items-center gap-2 font-display text-2xl font-bold tracking-tight text-foreground">
          <Building2 className="h-6 w-6" />
          Company &amp; Contracts
        </h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Your contractor license and the terms that appear on client contracts.
        </p>
      </div>

      <section className="rounded-xl bg-card px-5 py-5 ring-1 ring-foreground/10">
        <p className="eyebrow text-brand">Licensing</p>
        <h2 className="font-display text-lg font-bold tracking-tight text-foreground">
          CSLB license number
        </h2>
        <p className="mt-1 text-sm text-muted-foreground">
          Required on California home-improvement contracts. It merges into the
          contract as <code className="num text-xs">{`{{company_license_number}}`}</code>.
        </p>

        <div className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end">
          <div className="flex-1 space-y-1.5">
            <Label htmlFor="license-number">License number</Label>
            <Input
              id="license-number"
              value={licenseNumber}
              onChange={(event) => setLicenseNumber(event.target.value)}
              placeholder="e.g. 1234567"
              disabled={companyLoading}
              className="num max-w-xs"
            />
          </div>
          <Button
            variant="brand"
            onClick={handleSaveLicense}
            disabled={!isDirty || updateCompany.isPending || companyLoading}
          >
            {updateCompany.isPending && (
              <Loader2 className="h-4 w-4 animate-spin" />
            )}
            Save license
          </Button>
        </div>
      </section>

      <ContractTermsEditor />
    </div>
  );
}
