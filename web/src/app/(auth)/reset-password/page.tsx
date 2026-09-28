"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { AlertCircle, CheckCircle2, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const MIN_PASSWORD_LENGTH = 8;

export default function ResetPasswordPage() {
  const [token, setToken] = useState<string | null>(null);
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Read the token from the query string on the client (avoids the
  // useSearchParams Suspense requirement, matching the login page).
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    setToken(params.get("token"));
  }, []);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (newPassword.length < MIN_PASSWORD_LENGTH) {
      setError(`Password must be at least ${MIN_PASSWORD_LENGTH} characters.`);
      return;
    }
    if (newPassword !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    setIsSubmitting(true);
    try {
      const response = await fetch("/api/auth/reset-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, new_password: newPassword }),
      });
      if (response.status === 204) {
        setDone(true);
      } else {
        const data = await response.json().catch(() => ({}));
        setError(data.detail ?? "This reset link is invalid or has expired.");
      }
    } catch {
      setError("Something went wrong. Please try again.");
    } finally {
      setIsSubmitting(false);
    }
  };

  const missingToken = token === null || token === "";

  return (
    <div className="flex min-h-screen items-center justify-center bg-white p-8">
      <div className="w-full max-w-md">
        <h1 className="mb-8 inline-flex items-center gap-2 text-3xl font-extrabold tracking-tight text-foreground">
          <span className="inline-block h-5 w-5 rounded-[4px] bg-brand" />
          ContractorHub
        </h1>

        {done ? (
          <div className="space-y-4">
            <div className="flex items-center gap-2.5 rounded-lg border border-green-200 bg-green-50 p-3.5 text-sm text-green-800">
              <CheckCircle2 className="h-5 w-5 flex-shrink-0" />
              <span>Your password has been reset. You can now sign in.</span>
            </div>
            <Link
              href="/login"
              className="inline-block text-sm font-medium text-brand hover:underline"
            >
              Go to sign in &rarr;
            </Link>
          </div>
        ) : missingToken ? (
          <div className="space-y-4">
            <div className="flex items-center gap-2.5 rounded-lg border border-red-200 bg-red-50 p-3.5 text-sm text-red-700">
              <AlertCircle className="h-5 w-5 flex-shrink-0" />
              <span>This reset link is missing or invalid. Request a new one.</span>
            </div>
            <Link
              href="/forgot-password"
              className="inline-block text-sm font-medium text-brand hover:underline"
            >
              Request a new link
            </Link>
          </div>
        ) : (
          <>
            <div className="mb-8">
              <h2 className="text-3xl font-bold tracking-tight text-gray-900">
                Set a new password
              </h2>
              <p className="mt-2 text-base text-gray-500">
                Choose a new password for your account.
              </p>
            </div>

            {error && (
              <div className="mb-5 flex items-center gap-2.5 rounded-lg border border-red-200 bg-red-50 p-3.5 text-sm text-red-700">
                <AlertCircle className="h-5 w-5 flex-shrink-0" />
                <span>{error}</span>
              </div>
            )}

            <form onSubmit={onSubmit} className="space-y-5">
              <div className="space-y-1.5">
                <Label htmlFor="new-password" className="text-base">
                  New Password
                </Label>
                <Input
                  id="new-password"
                  type="password"
                  autoComplete="new-password"
                  className="h-11 text-base"
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  required
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="confirm-password" className="text-base">
                  Confirm New Password
                </Label>
                <Input
                  id="confirm-password"
                  type="password"
                  autoComplete="new-password"
                  className="h-11 text-base"
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  required
                />
              </div>

              <Button
                type="submit"
                variant="brand"
                className="h-11 w-full text-base font-semibold"
                disabled={isSubmitting}
              >
                {isSubmitting ? (
                  <>
                    <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                    Resetting...
                  </>
                ) : (
                  "Reset password"
                )}
              </Button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
