"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Eye, EyeOff, AlertCircle, Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "sonner";
import { useAppDispatch } from "@/store/hooks";
import { setAuthUser } from "@/store/slices/auth-slice";
import type { AuthUser } from "@/types/api";

const loginSchema = z.object({
  email: z.string().email("Please enter a valid email address"),
  password: z.string().min(1, "Password is required"),
});

type LoginFormValues = z.infer<typeof loginSchema>;

export default function LoginPage() {
  const router = useRouter();
  const dispatch = useAppDispatch();
  const [showPassword, setShowPassword] = useState(false);
  const [loginError, setLoginError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const {
    register,
    handleSubmit,
    formState: { errors },
    watch,
  } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema),
  });

  // Clear login error banner when user starts typing
  useEffect(() => {
    const subscription = watch(() => {
      setLoginError(null);
    });
    return () => subscription.unsubscribe();
  }, [watch]);

  // Check for session_expired reason on mount
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    if (params.get("reason") === "session_expired") {
      setLoginError("Your session expired. Please log in again.");
    }
  }, []);

  const onSubmit = async (data: LoginFormValues) => {
    setIsSubmitting(true);
    setLoginError(null);

    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: data.email, password: data.password }),
      });

      if (response.ok) {
        const userMeta = (await response.json()) as AuthUser;
        dispatch(
          setAuthUser({
            displayName: userMeta.display_name ?? userMeta.email ?? null,
            companyName: userMeta.company_name ?? null,
            roles: userMeta.roles,
          })
        );
        // ALWAYS redirect to dashboard home — never honor redirectTo
        router.push("/");
      } else if (response.status === 401 || response.status === 422) {
        setLoginError("Invalid email or password");
      } else {
        setLoginError("Something went wrong. Please try again.");
      }
    } catch {
      setLoginError("Something went wrong. Please try again.");
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex min-h-screen">
      {/* Left panel — ink chrome with blueprint grid + hi-vis (hidden on mobile) */}
      <div className="relative hidden flex-1 flex-col justify-center overflow-hidden bg-sidebar p-14 text-white md:flex">
        <div className="blueprint-grid pointer-events-none absolute inset-0 text-white/70" />
        <div className="absolute inset-x-0 top-0 h-1 bg-brand" />
        <div className="relative max-w-md">
          <p className="eyebrow mb-6 text-brand">Contractor operations</p>
          <h1 className="mb-5 flex items-center gap-3 text-5xl font-extrabold tracking-tight">
            <span className="inline-block h-7 w-7 rounded-[5px] bg-brand" />
            ContractorHub
          </h1>
          <p className="text-2xl leading-relaxed text-white/70">
            Run every job, quote, and invoice from one command center.
          </p>
          <div className="mt-10 space-y-4 text-lg text-white/80">
            <div className="flex items-center gap-3">
              <span className="inline-block h-2 w-2 rounded-[2px] bg-brand" />
              <span>Real-time job tracking and scheduling</span>
            </div>
            <div className="flex items-center gap-3">
              <span className="inline-block h-2 w-2 rounded-[2px] bg-brand" />
              <span>Automated quotes and invoicing</span>
            </div>
            <div className="flex items-center gap-3">
              <span className="inline-block h-2 w-2 rounded-[2px] bg-brand" />
              <span>Contractor and client management</span>
            </div>
          </div>
        </div>
      </div>

      {/* Right panel — login form */}
      <div className="flex flex-col justify-center items-center flex-1 p-8 bg-white">
        <div className="w-full max-w-md">
          {/* Mobile logo */}
          <div className="mb-8 md:hidden text-center">
            <h1 className="inline-flex items-center gap-2 text-3xl font-extrabold tracking-tight text-foreground">
              <span className="inline-block h-5 w-5 rounded-[4px] bg-brand" />
              ContractorHub
            </h1>
          </div>

          <div className="mb-8">
            <h2 className="text-3xl font-bold tracking-tight text-gray-900">
              Sign in
            </h2>
            <p className="mt-2 text-base text-gray-500">
              Enter your credentials to access your dashboard
            </p>
          </div>

          {/* Inline error banner */}
          {loginError && (
            <div className="mb-5 flex items-center gap-2.5 rounded-lg border border-red-200 bg-red-50 p-3.5 text-sm text-red-700">
              <AlertCircle className="h-5 w-5 flex-shrink-0" />
              <span>{loginError}</span>
            </div>
          )}

          <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
            {/* Email field */}
            <div className="space-y-1.5">
              <Label htmlFor="email" className="text-base">
                Email
              </Label>
              <Input
                id="email"
                type="email"
                placeholder="admin@example.com"
                autoComplete="email"
                className="h-11 text-base"
                {...register("email")}
                aria-invalid={!!errors.email}
              />
              {errors.email && (
                <p className="text-sm text-red-600">{errors.email.message}</p>
              )}
            </div>

            {/* Password field */}
            <div className="space-y-1.5">
              <Label htmlFor="password" className="text-base">
                Password
              </Label>
              <div className="relative">
                <Input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  placeholder="••••••••"
                  autoComplete="current-password"
                  className="h-11 text-base pr-11"
                  {...register("password")}
                  aria-invalid={!!errors.password}
                />
                <button
                  type="button"
                  className="absolute inset-y-0 right-0 flex items-center px-3 text-gray-400 hover:text-gray-600"
                  onClick={() => setShowPassword((v) => !v)}
                  aria-label={showPassword ? "Hide password" : "Show password"}
                >
                  {showPassword ? (
                    <EyeOff className="h-5 w-5" />
                  ) : (
                    <Eye className="h-5 w-5" />
                  )}
                </button>
              </div>
              {errors.password && (
                <p className="text-sm text-red-600">{errors.password.message}</p>
              )}
            </div>

            {/* Forgot password */}
            <div className="flex justify-end">
              <button
                type="button"
                className="text-sm font-medium text-muted-foreground hover:text-foreground"
                onClick={() =>
                  toast("Contact your administrator", {
                    description: "Password reset is managed by your system administrator.",
                  })
                }
              >
                Forgot password?
              </button>
            </div>

            {/* Submit button */}
            <Button
              type="submit"
              variant="brand"
              className="w-full h-11 text-base font-semibold"
              disabled={isSubmitting}
            >
              {isSubmitting ? (
                <>
                  <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                  Signing in...
                </>
              ) : (
                "Sign In"
              )}
            </Button>
          </form>
        </div>
      </div>
    </div>
  );
}
