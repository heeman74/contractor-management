import { redirect } from "next/navigation";
import { getServerUser } from "@/lib/auth";
import { CompanySettingsForm } from "./_components/company-settings-form";

/**
 * Company settings — edit the CSLB license_number (PATCH /companies/{id}) and the
 * contract-terms template. Rendered as a Server Component so the company_id comes
 * from the verified JWT cookie (getServerUser) rather than client state, which is
 * not persisted across reloads. The permission gate (contracts.manage) and the
 * forms live in the client component below.
 */
export default async function CompanySettingsPage() {
  const user = await getServerUser();
  if (!user) {
    redirect("/login");
  }

  return <CompanySettingsForm companyId={user.company_id} />;
}
