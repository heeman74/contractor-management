import { redirect } from "next/navigation";

import { getServerUser } from "@/lib/auth";
import { SettingsIndex } from "./_components/settings-index";

/**
 * The settings hub.
 *
 * Breadcrumbs are built from path segments, so every settings page rendered a
 * link to `/settings` — which no page answered. Next prefetched it on arrival
 * and it 404'd, as did clicking it. A hub is the better answer than making the
 * crumb inert: the sections are permission-gated and sit in different places in
 * the sidebar, so one page listing what this user can actually reach is useful
 * on its own.
 */
export default async function SettingsPage() {
  const user = await getServerUser();
  if (!user) {
    redirect("/login");
  }

  return <SettingsIndex />;
}
