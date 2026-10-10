"use client";

import { useState } from "react";
import { Loader2, Mail, Send } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  useClearCompanyEmailApi,
  useClearCompanySmtp,
  useCompany,
  useCompanyEmailStatus,
  useTestCompanyEmail,
  useUpdateCompany,
} from "@/lib/api/contracts";
import { usePermissions } from "@/lib/hooks/usePermissions";
import type { EmailTestResult, EmailTestTarget } from "@/types/api";

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

/** The three ways mail can leave. Exactly one is in force at a time. */
type SendMethod = "relay" | "provider" | "mailbox";

const METHODS: readonly { value: SendMethod; label: string; description: string }[] = [
  {
    value: "relay",
    label: "The server's mail account",
    description:
      "Nothing to set up. Mail goes out under your company name with your address as the reply-to, so replies still reach you.",
  },
  {
    value: "provider",
    label: "An email provider over HTTPS",
    description:
      "Resend, SendGrid or Postmark. Reports whether each message was delivered, bounced or marked as spam — which SMTP never tells you — and works where outgoing SMTP is blocked.",
  },
  {
    value: "mailbox",
    label: "Your own mailbox over SMTP",
    description:
      "Mail is sent from your address and appears in your Sent folder. Needs a host that allows outgoing SMTP.",
  },
];

interface CompanyEmailFormProps {
  companyId: string;
}

// Mail a provider can never be made to send from: the domain belongs to the
// mailbox host, so there is no DNS record its owner could add to verify it.
// Saying so here saves a round trip to a 403 that reads like a setup step still
// to be done, when it is one that can never be done.
const CONSUMER_MAIL_DOMAINS = [
  "gmail.com",
  "googlemail.com",
  "yahoo.com",
  "outlook.com",
  "hotmail.com",
  "live.com",
  "icloud.com",
  "me.com",
  "aol.com",
  "proton.me",
  "protonmail.com",
];

/** A provider's own trial sender, which needs no domain of yours. */
const TRIAL_SENDER_DOMAINS = ["resend.dev"];

function domainOf(address: string): string {
  return address.trim().split("@").pop()?.toLowerCase() ?? "";
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
  const clearEmailApi = useClearCompanyEmailApi(companyId);

  const [fromName, setFromName] = useState("");
  const [fromAddress, setFromAddress] = useState("");
  const [smtpHost, setSmtpHost] = useState("");
  const [smtpPort, setSmtpPort] = useState("");
  const [smtpUser, setSmtpUser] = useState("");
  const [smtpPassword, setSmtpPassword] = useState("");
  const [apiProvider, setApiProvider] = useState("");
  const [apiKey, setApiKey] = useState("");
  const [method, setMethod] = useState<SendMethod>("relay");
  const [lastTest, setLastTest] = useState<EmailTestResult | null>(null);
  const [testTarget, setTestTarget] = useState<EmailTestTarget>("me");

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
    setApiProvider(company.email_api_provider ?? "");
    setApiKey("");
    // Whichever is configured is the one in force — the server prefers the
    // provider, so that ordering is reflected here rather than left implicit.
    setMethod(
      company.email_api_configured
        ? "provider"
        : company.smtp_configured
          ? "mailbox"
          : "relay"
    );
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
  const storedMethod: SendMethod = company?.email_api_configured
    ? "provider"
    : company?.smtp_configured
      ? "mailbox"
      : "relay";

  // The test exercises what the server has stored, not what is on screen, so
  // unsaved changes have to be visible and the test has to save first.
  const isDirty =
    method !== storedMethod ||
    fromName !== (company?.email_from_name ?? "") ||
    fromAddress !== (company?.email_from_address ?? "") ||
    smtpHost !== (company?.smtp_host ?? "") ||
    smtpPort !== storedPort ||
    smtpUser !== (company?.smtp_user ?? "") ||
    smtpPassword.trim() !== "" ||
    apiProvider !== (company?.email_api_provider ?? "") ||
    apiKey.trim() !== "";

  // A credential already stored counts as present: the field is blank after a
  // save by design, and treating that as incomplete greys out Save and strands
  // every other field in the section.
  const mailboxReady =
    smtpHost.trim() !== "" &&
    smtpUser.trim() !== "" &&
    (smtpPassword.trim() !== "" ||
      company?.smtp_configured === true ||
      (company?.smtp_host ?? "") !== "");
  const providerReady =
    apiProvider !== "" &&
    (apiKey.trim() !== "" || company?.email_api_configured === true);
  // A provider will not accept a message with no From address, and neither
  // will the relay know who to put in the reply-to.
  const senderReady = method === "relay" || fromAddress.trim() !== "";

  const canSave =
    senderReady &&
    (method === "relay" ||
      (method === "mailbox" ? mailboxReady : providerReady));

  // Only meaningful for a provider: sending from a consumer mailbox over SMTP
  // is exactly what SMTP is for, and the relay never uses this as the From.
  const senderDomain = domainOf(fromAddress);
  const senderCannotBeVerified =
    method === "provider" && CONSUMER_MAIL_DOMAINS.includes(senderDomain);
  const senderIsTrialOnly =
    method === "provider" && TRIAL_SENDER_DOMAINS.includes(senderDomain);

  const incompleteReason = !senderReady
    ? "A sending address is needed, so there is something to send from."
    : method === "mailbox"
      ? "A mailbox needs a server, a username and a password."
      : "A provider needs to be chosen, with its API key.";

  function handleSave(afterSaved?: () => void) {
    if (updateCompany.isPending || !canSave) return;

    updateCompany.mutate(
      {
        email_from_name: emptyToNull(fromName),
        email_from_address: emptyToNull(fromAddress),
        ...(method === "mailbox"
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
        ...(method === "provider"
          ? {
              email_api_provider: apiProvider,
              // Omitted when blank: the stored key stays as it is.
              ...(apiKey.trim() === "" ? {} : { email_api_key: apiKey.trim() }),
            }
          : {}),
      },
      {
        onSuccess: () => {
          setSmtpPassword("");
          setApiKey("");
          setLastTest(null);
          discardUnchosenMethods(() => {
            toast.success("Email settings saved.");
            afterSaved?.();
          });
        },
        onError: (error) =>
          toast.error(error.message || "Could not save the email settings.", {
            duration: Infinity,
          }),
      }
    );
  }

  /**
   * Remove whatever the chosen method is not, so the stored settings say the
   * same thing the screen does.
   *
   * Without this, choosing a provider while a mailbox is still stored leaves
   * both on the server, and which one carries the mail is decided by a
   * preference order nobody can see from here.
   */
  function discardUnchosenMethods(done: () => void) {
    const failed = () =>
      toast.error(
        "Saved, but the previous method could not be removed. Both are stored, " +
          "and the provider is the one that will be used.",
        { duration: Infinity }
      );

    if (method !== "mailbox" && company?.smtp_configured) {
      clearSmtp.mutate(undefined, {
        onSuccess: () =>
          method !== "provider" && company?.email_api_configured
            ? clearEmailApi.mutate(undefined, { onSuccess: done, onError: failed })
            : done(),
        onError: failed,
      });
      return;
    }
    if (method !== "provider" && company?.email_api_configured) {
      clearEmailApi.mutate(undefined, { onSuccess: done, onError: failed });
      return;
    }
    done();
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
          <Label htmlFor="email-from-address">Sending address</Label>
          <Input
            id="email-from-address"
            type="email"
            value={fromAddress}
            onChange={(event) => setFromAddress(event.target.value)}
            placeholder="quotes@yourcompany.com"
          />
          {/* It was labelled "reply-to", which is what it becomes on only one
              of the three methods. On the other two it is the From a client
              sees — so the label read as though the From were fixed somewhere
              out of reach. */}
          <p className="text-xs text-muted-foreground">
            {method === "relay"
              ? "The server's account sends, so this is where client replies go."
              : method === "provider"
                ? "The From address your clients see. It must be on a domain verified with your provider — a trial sender like onboarding@resend.dev works only for testing."
                : "The From address your clients see. It usually has to match the mailbox you sign in to below."}
          </p>

          {senderCannotBeVerified ? (
            <p
              role="status"
              className="rounded-lg bg-amber-500/10 px-3 py-2 text-xs text-amber-800 ring-1 ring-amber-500/30 dark:text-amber-200"
            >
              <strong>{senderDomain}</strong> can never be verified with a
              provider — the domain belongs to the mailbox host, not to you, so
              there is no DNS record you could add. Either verify a domain you
              own and send from that, or choose &ldquo;your own mailbox over
              SMTP&rdquo; below, which signs in to this address and is therefore
              allowed to send as it.
            </p>
          ) : null}

          {senderIsTrialOnly ? (
            <p
              role="status"
              className="rounded-lg bg-amber-500/10 px-3 py-2 text-xs text-amber-800 ring-1 ring-amber-500/30 dark:text-amber-200"
            >
              A trial sender. It is accepted as a From, but it only delivers
              to the address your provider account is registered with — so a
              test reaches you only if that is also your signed-in address, and
              it can never reach a client. Verify a domain you own before
              sending quotes from it.
            </p>
          ) : null}
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
          How mail is sent
        </h3>
        <p className="mt-1 text-sm text-muted-foreground">
          One of these carries your mail. Choosing one puts the others away —
          previously both could be filled in at once and only the server knew
          which it would use.
        </p>

        <div
          role="radiogroup"
          aria-label="How mail is sent"
          className="mt-4 space-y-2"
        >
          {METHODS.map((option) => {
            const unavailable =
              option.value === "relay" && emailStatus?.relay_available === false;
            return (
              <label
                key={option.value}
                className={`flex gap-3 rounded-lg px-3 py-2.5 ring-1 transition ${
                  method === option.value
                    ? "bg-brand/10 ring-brand/40"
                    : "ring-foreground/10 hover:ring-foreground/20"
                } ${unavailable ? "opacity-60" : ""}`}
              >
                <input
                  type="radio"
                  name="email-method"
                  value={option.value}
                  checked={method === option.value}
                  disabled={unavailable}
                  onChange={() => setMethod(option.value)}
                  className="mt-1"
                />
                <span className="min-w-0">
                  <span className="block text-sm font-medium text-foreground">
                    {option.label}
                    {unavailable ? " — not available on this server" : ""}
                  </span>
                  <span className="block text-sm text-muted-foreground">
                    {option.description}
                  </span>
                </span>
              </label>
            );
          })}
        </div>

        {method === "provider" ? (
          <div className="mt-5">
            <p className="text-sm text-muted-foreground">
              Your sending domain has to be verified with the provider. To try
              it before setting up DNS, Resend accepts{" "}
              <code className="rounded bg-muted px-1 py-0.5 text-xs">
                onboarding@resend.dev
              </code>{" "}
              as the reply-to address above — it only delivers to the address
              your Resend account is registered with, which is enough for a
              test.
            </p>

            <div className="mt-4 grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <Label htmlFor="email-api-provider">Provider</Label>
                <select
                  id="email-api-provider"
                  value={apiProvider}
                  onChange={(event) => setApiProvider(event.target.value)}
                  className="h-11 w-full rounded-lg border border-input bg-transparent px-2.5 text-base outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 md:text-sm"
                >
                  <option value="">Choose one</option>
                  <option value="resend">Resend</option>
                  <option value="sendgrid">SendGrid</option>
                  <option value="postmark">Postmark</option>
                </select>
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="email-api-key">
                  {company?.email_api_configured ? "Replace API key" : "API key"}
                </Label>
                <Input
                  id="email-api-key"
                  type="password"
                  autoComplete="off"
                  value={apiKey}
                  onChange={(event) => setApiKey(event.target.value)}
                  placeholder={
                    company?.email_api_configured ? "Leave blank to keep" : ""
                  }
                />
                <p className="text-xs text-muted-foreground">
                  Postmark calls this a server API token; the others call it an
                  API key.
                </p>
              </div>
            </div>
          </div>
        ) : null}

        {method === "mailbox" ? (
          <div className="mt-5 grid gap-4 sm:grid-cols-2">
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
                  scroll, and browsers differ on what they accept typed or
                  pasted. The port is three digits — a plain field with a
                  numeric keypad hint is less to go wrong. */}
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
                587 for STARTTLS, 465 if the connection times out — some
                networks drop 587 without answering.
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
              <p className="text-xs text-muted-foreground">{PASSWORD_HELP}</p>
            </div>
          </div>
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
              ? `Handed to the mail server, addressed to ${lastTest.recipient}`
              : `Nothing was sent to ${lastTest.recipient}`}
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
          // Only blocked when there are unsaved changes that cannot be saved:
          // testing what is already stored does not require the form to be
          // complete, and refusing it would hide the very error being looked for.
          disabled={
            testEmail.isPending || updateCompany.isPending || (isDirty && !canSave)
          }
          onClick={() => {
            const runTest = () =>
              testEmail.mutate(testTarget, {
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

        <div className="w-full space-y-1.5">
          <Label htmlFor="test-target">Send the test to</Label>
          <select
            id="test-target"
            value={testTarget}
            onChange={(event) =>
              setTestTarget(event.target.value as EmailTestTarget)
            }
            className="h-10 rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
          >
            <option value="me">My own address</option>
            <option value="sender" disabled={fromAddress.trim() === ""}>
              The reply-to address
              {fromAddress.trim() === "" ? " — none set" : ` (${fromAddress})`}
            </option>
          </select>
          <p className="text-xs text-muted-foreground">
            One of these two, never an address typed in — otherwise this page
            would send mail as your company to anyone. A provider&apos;s trial
            sender usually only delivers to the address its own account uses,
            which is the reply-to one here, not yours.
          </p>
        </div>

        {!canSave ? (
          <p className="text-xs text-amber-700 dark:text-amber-300">
            {incompleteReason}
          </p>
        ) : null}
      </div>
    </section>
  );
}
