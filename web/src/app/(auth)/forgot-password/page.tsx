"use client";

import { useState } from "react";
import Link from "next/link";
import { AlertCircle, Loader2, MailCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const onSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setIsSubmitting(true);
    try {
      const response = await fetch("/api/auth/forgot-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      if (response.ok) {
        setSubmitted(true);
      } else {
        setError("Something went wrong. Please try again.");
      }
    } catch {
      setError("Something went wrong. Please try again.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-white p-8">
      <div className="w-full max-w-md">
        <h1 className="mb-8 inline-flex items-center gap-2 text-3xl font-extrabold tracking-tight text-foreground">
          <span className="inline-block h-5 w-5 rounded-[4px] bg-brand" />
          ContractorHub
        </h1>

        {submitted ? (
          <div className="space-y-4">
            <div className="flex items-center gap-2.5 rounded-lg border border-green-200 bg-green-50 p-3.5 text-sm text-green-800">
              <MailCheck className="h-5 w-5 flex-shrink-0" />
              <span>
                If an account exists for that email, a password-reset link is on its way.
                Check your inbox.
              </span>
            </div>
            <Link
              href="/login"
              className="inline-block text-sm font-medium text-brand hover:underline"
            >
              &larr; Back to sign in
            </Link>
          </div>
        ) : (
          <>
            <div className="mb-8">
              <h2 className="text-3xl font-bold tracking-tight text-gray-900">
                Forgot password?
              </h2>
              <p className="mt-2 text-base text-gray-500">
                Enter your email and we&apos;ll send you a link to reset it.
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
                <Label htmlFor="email" className="text-base">
                  Email
                </Label>
                <Input
                  id="email"
                  type="email"
                  placeholder="you@example.com"
                  autoComplete="email"
                  className="h-11 text-base"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                />
              </div>

              <Button
                type="submit"
                variant="brand"
                className="h-11 w-full text-base font-semibold"
                disabled={isSubmitting || !email.trim()}
              >
                {isSubmitting ? (
                  <>
                    <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                    Sending...
                  </>
                ) : (
                  "Send reset link"
                )}
              </Button>

              <Link
                href="/login"
                className="block text-center text-sm font-medium text-muted-foreground hover:text-foreground"
              >
                Back to sign in
              </Link>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
