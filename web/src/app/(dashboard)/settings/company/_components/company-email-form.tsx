"use client";

import { useState } from "react";
import { Loader2, Mail, Send } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  useClearCompanySmtp,
  useCompany,
  useCompanyEmailStatus,
  useTestCompanyEmail,
  useUpdateCompany,
} from "@/lib/api/contracts";
import { usePermissions } from "@/lib/hooks/usePermissions";
import type { EmailTestResult } from "@/types/api";

/**
 * Where this company's mail comes from.
 *
 * Quotes briefly went out through one server-wide account, so every company's
 * mail was addressed from the operator's mailbox. Writing the company's address
 * into From does not fix that — a provider only accepts a sender it has
 * authenticated — so there are two tiers here: an address, which the server's
 * account uses as the reply-to, and the company's own mailbox, which actually
 * sends as them.
 *
 * The password is write-only. It is sent once, stored encrypted, and no response
 * ever returns it, so the field stays blank on load and an empty value means
 * "leave it alone".
 */

interface CompanyEmailFormProps {
  companyId: string;
}

const PASSWORD_HELP =
  "Your provider's key goes here — SMTP has no separate key field. Gmail needs " +
  "an app password, not your account password (generate one with 2-step " +
  "verification on). SendGrid uses the username \u201capikey\u201d with the API " +
  "key as the password.";

function emptyToNull(value: string): string | null {
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
}

export function CompanyEmailForm({ companyId }: CompanyEmailFormProps) {
  const { can, isLoading: permissionsLoading } = usePermissions();
  const { data: company } = useCompany(companyId);
  const { data: emailStatus } = useCompanyEmailStatus(companyId);
  const updateCompany = useUpdateCompany(companyId);
  const testEmail = useTestCompanyEmail(companyId);
  const clearSmtp = useClearCompanySmtp(companyId);

  const [fromName, setFromName] = useState("");
  const [fromAddress, setFromAddress] = useState("");
  const [smtpHost, setSmtpHost] = useState("");
  const [smtpPort, setSmtpPort] = useState("");
  const [smtpUser, setSmtpUser] = useState("");
  const [smtpPassword, setSmtpPassword] = useState("");
  const [lastTest, setLastTest] = useState<EmailTestResult | null>(null);

  // Render-time sync, matching the profile form: seed the fields once the
  // company loads rather than setting state from an effect.
  const [syncedId, setSyncedId] = useState<string | null>(null);
  if (company && company.id !== syncedId) {
    setSyncedId(company.id);
    setFromName(company.email_from_name ?? "");
    setFromAddress(company.email_from_address ?? "");
    setSmtpHost(company.smtp_host ?? "");
    setSmtpPort(company.smtp_port ? String(company.smtp_port) : "");
    setSmtpUser(company.smtp_user ?? "");
    setSmtpPassword("");
  }

  if (permissionsLoading) {
    return <div className="h-64 animate-pulse rounded-xl bg-muted" />;
  }

  if (!can("company.settings.manage")) {
    return null;
  }

  // The test exercises what the server has stored, not what is on screen. Typing
  // a new port and pressing test reported a failure against the old one, naming
  // a port the user could see they had just changed — so unsaved changes have to
  // be visible, and the test has to save first.
  const storedPort = company?.smtp_port ? String(company.smtp_port) : "";
  const isDirty =
    fromName !== (company?.email_from_name ?? "") ||
    fromAddress !== (company?.email_from_address ?? "") ||
    smtpHost !== (company?.smtp_host ?? "") ||
    smtpPort !== storedPort ||
    smtpUser !== (company?.smtp_user ?? "") ||
    smtpPassword.trim() !== "";

  // A mailbox needs all three. Offering a partial save would only surface as a
  // database rejection, since the columns are constrained to travel together.
  const wantsMailbox =
    smtpHost.trim() !== "" || smtpUser.trim() !== "" || smtpPassword.trim() !== "";
  // A password already stored counts as present. Without this, a saved mailbox
  // whose password field is blank by design reads as incomplete, Save goes grey,
  // and the port cannot be changed — the field looks editable and nothing can be
  // done with it. A stored host is evidence enough, so a backend that does not
  // report smtp_configured cannot cause that either.
  const passwordAlreadyStored =
    company?.smtp_configured === true || (company?.smtp_host ?? "") !== "";
  const mailboxIsComplete =
    smtpHost.trim() !== "" &&
    smtpUser.trim() !== "" &&
    (smtpPassword.trim() !== "" || passwordAlreadyStored);
  const canSave = !wantsMailbox || mailboxIsComplete;

  function handleSave(afterSaved?: () => void) {
    if (updateCompany.isPending || !canSave) return;
    updateCompany.mutate(
      {
        email_from_name: emptyToNull(fromName),
        email_from_address: emptyToNull(fromAddress),
        ...(wantsMailbox
          ? {
              smtp_host: emptyToNull(smtpHost),
              smtp_port: smtpPort.trim() === "" ? null : Number(smtpPort),
              smtp_user: emptyToNull(smtpUser),
              // Omitted when blank: the stored password stays as it is.
              ...(smtpPassword.trim() === ""
                ? {}
                : { smtp_password: smtpPassword.trim() }),
            }
          : {}),
      },
      {
        onSuccess: () => {
          setSmtpPassword("");
          setLastTest(null);
          toast.success("Email settings saved.");
          afterSaved?.();
        },
        onError: (error) =>
          toast.error(error.message || "Could not save the email settings.", {
            duration: Infinity,
          }),
      }
    );
  }

  return (
    <section className="rounded-xl bg-card px-5 py-5 ring-1 ring-foreground/10">
      <p className="eyebrow text-brand">Email</p>
      <h2 className="flex items-center gap-2 font-display text-lg font-bold tracking-tight text-foreground">
        <Mail className="h-5 w-5" />
        Sending email
      </h2>
      <p className="mt-1 text-sm text-muted-foreground">
        Who quotes and invoices come from when your clients receive them.
      </p>

      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="email-from-name">Sender name</Label>
          <Input
            id="email-from-name"
            value={fromName}
            onChange={(event) => setFromName(event.target.value)}
            placeholder={company?.name ?? "Your company"}
          />
          <p className="text-xs text-muted-foreground">
            Shown as the sender. Defaults to your company name.
          </p>
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="email-from-address">Reply-to address</Label>
          <Input
            id="email-from-address"
            type="email"
            value={fromAddress}
            onChange={(event) => setFromAddress(event.target.value)}
            placeholder="quotes@yourcompany.com"
          />
          <p className="text-xs text-muted-foreground">
            Where client replies go.
          </p>
        </div>
      </div>

      {emailStatus && !emailStatus.can_send ? (
        <div
          role="status"
          className="mt-5 rounded-lg bg-amber-500/10 px-4 py-3 text-sm text-amber-800 ring-1 ring-amber-500/30 dark:text-amber-200"
        >
          <p className="font-semibold">Quotes cannot be emailed yet</p>
          <p className="mt-0.5">
            This server has no mail account of its own, so the only way to send
            is through your own mailbox below.
          </p>
        </div>
      ) : null}

      {emailStatus?.can_send ? (
        <p className="mt-5 text-sm text-muted-foreground">
          Clients currently see{" "}
          <span className="font-medium text-foreground">{emailStatus.sender}</span>
          {emailStatus.reply_to ? (
            <>
              , with replies going to{" "}
              <span className="font-medium text-foreground">
                {emailStatus.reply_to}
              </span>
            </>
          ) : null}
          .
        </p>
      ) : null}

      <div className="mt-6 border-t border-foreground/10 pt-5">
        <h3 className="font-display text-sm font-bold tracking-tight text-foreground">
          Send through your own mailbox
          {emailStatus && !emailStatus.relay_available ? (
            <span className="ml-2 rounded bg-amber-500/15 px-1.5 py-0.5 text-xs font-semibold text-amber-800 dark:text-amber-200">
              Required
            </span>
          ) : null}
        </h3>
        <p className="mt-1 text-sm text-muted-foreground">
          {emailStatus && !emailStatus.relay_available
            ? "This server has no mail account, so these details are what send your quotes. Mail goes out from your address and appears in your Sent folder."
            : "Optional. With this set, mail is sent from your address and appears in your Sent folder. Without it, the server sends on your behalf and replies still reach you."}
        </p>

        <div className="mt-4 grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="smtp-host">SMTP server</Label>
            <Input
              id="smtp-host"
              value={smtpHost}
              onChange={(event) => setSmtpHost(event.target.value)}
              placeholder="smtp.gmail.com"
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="smtp-port">Port</Label>
            {/* Not type="number": its spinner changes the value on a stray
                scroll, and browsers differ on what they accept typed or pasted.
                The port is three digits — a plain field with a numeric keypad
                hint is less to go wrong. */}
            <Input
              id="smtp-port"
              inputMode="numeric"
              value={smtpPort}
              onChange={(event) =>
                setSmtpPort(event.target.value.replace(/[^0-9]/g, ""))
              }
              placeholder="587"
            />
            <p className="text-xs text-muted-foreground">
              587 for STARTTLS, 465 if the connection times out — some networks
              drop 587 without answering.
            </p>
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="smtp-user">Username</Label>
            <Input
              id="smtp-user"
              value={smtpUser}
              onChange={(event) => setSmtpUser(event.target.value)}
              placeholder="you@yourcompany.com"
            />
          </div>

          <div className="space-y-1.5">
            <Label htmlFor="smtp-password">
              {company?.smtp_configured ? "Replace password" : "Password"}
            </Label>
            <Input
              id="smtp-password"
              type="password"
              autoComplete="new-password"
              value={smtpPassword}
              onChange={(event) => setSmtpPassword(event.target.value)}
              placeholder={company?.smtp_configured ? "Leave blank to keep" : ""}
            />
            <p className="text-xs text-muted-foreground">
              {PASSWORD_HELP}
            </p>
          </div>
        </div>

        {company?.smtp_configured ? (
          <Button
            variant="outline"
            size="sm"
            className="mt-4"
            disabled={clearSmtp.isPending}
            onClick={() =>
              clearSmtp.mutate(undefined, {
                onSuccess: () => {
                  setSmtpHost("");
                  setSmtpPort("");
                  setSmtpUser("");
                  setSmtpPassword("");
                  setLastTest(null);
                  toast.success("Your mailbox was removed.");
                },
                onError: () =>
                  toast.error("Could not remove the mailbox. Try again.", {
                    duration: Infinity,
                  }),
              })
            }
          >
            {clearSmtp.isPending ? "Removing…" : "Stop using my mailbox"}
          </Button>
        ) : null}
      </div>

      {lastTest ? (
        <div
          role="status"
          className={`mt-5 rounded-lg px-4 py-3 text-sm ring-1 ${
            lastTest.delivered
              ? "bg-emerald-500/10 text-emerald-700 ring-emerald-500/30 dark:text-emerald-300"
              : "bg-amber-500/10 text-amber-800 ring-amber-500/30 dark:text-amber-200"
          }`}
        >
          <p className="font-semibold">
            {lastTest.delivered
              ? `Test sent to ${lastTest.recipient}`
              : "Nothing was sent"}
          </p>
          <p className="mt-0.5">{lastTest.detail}</p>
          {isDirty ? (
            <p className="mt-1 font-medium">
              You have unsaved changes — this result describes the settings as
              they were saved.
            </p>
          ) : null}
        </div>
      ) : null}

      <div className="mt-5 flex flex-wrap items-center gap-3">
        <Button onClick={() => handleSave()} disabled={updateCompany.isPending || !canSave}>
          {updateCompany.isPending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Saving…
            </>
          ) : (
            "Save email settings"
          )}
        </Button>

        <Button
          variant="outline"
          disabled={testEmail.isPending || updateCompany.isPending || !canSave}
          onClick={() => {
            const runTest = () =>
              testEmail.mutate(undefined, {
                onSuccess: setLastTest,
                onError: (error) =>
                  toast.error(error.message || "Could not run the test.", {
                    duration: Infinity,
                  }),
              });
            // Saving first, because the test reads stored settings — otherwise it
            // reports on a configuration the screen no longer shows.
            if (isDirty) handleSave(runTest);
            else runTest();
          }}
        >
          {testEmail.isPending || updateCompany.isPending ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Sending…
            </>
          ) : (
            <>
              <Send className="mr-2 h-4 w-4" />
              {isDirty ? "Save and send a test" : "Send a test to myself"}
            </>
          )}
        </Button>

        {!canSave ? (
          <p className="text-xs text-amber-700 dark:text-amber-300">
            A mailbox needs a server, a username and a password.
          </p>
        ) : null}
      </div>
    </section>
  );
}
