import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";
import { StoreProvider } from "@/store/provider";
import { QueryProvider } from "@/components/providers/query-provider";
import { Toaster } from "@/components/ui/sonner";
import NextTopLoader from "nextjs-toploader";

// Self-hosted rather than fetched through next/font/google, which downloads
// them during the build: the deploy build failed when the builder could not
// reach Google Fonts, and a web deploy that cannot build ships nothing. See
// ./fonts/README.md.
//
// Each file is the variable version covering the whole weight axis, so one
// declaration serves every weight the app uses.
const geistSans = localFont({
  src: "./fonts/geist-latin.woff2",
  variable: "--font-geist-sans",
  weight: "100 900",
  display: "swap",
});

const geistMono = localFont({
  src: "./fonts/geist-mono-latin.woff2",
  variable: "--font-geist-mono",
  weight: "100 900",
  display: "swap",
});

// Archivo — industrial grotesque used with restraint on display headings.
const archivo = localFont({
  src: "./fonts/archivo-latin.woff2",
  variable: "--font-archivo",
  weight: "600 800",
  display: "swap",
});

export const metadata: Metadata = {
  title: "ContractorHub",
  description: "Web admin dashboard for ContractorHub",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        // Browser extensions (e.g. Grammarly) inject attributes like
        // data-gr-ext-installed onto <body> before React hydrates, causing a
        // benign attribute-only hydration mismatch. Suppress it for this
        // element — it only affects <body>'s own attributes, not app content.
        suppressHydrationWarning
        className={`${geistSans.variable} ${geistMono.variable} ${archivo.variable} antialiased`}
      >
        {/* NProgress-style thin progress bar for route transitions */}
        <NextTopLoader color="#f5a623" showSpinner={false} />
        <StoreProvider>
          <QueryProvider>{children}</QueryProvider>
        </StoreProvider>
        {/*
         * Error toasts MUST persist until manually dismissed.
         * Always call toast.error("message", { duration: Infinity }) at each call site.
         * toastOptions below is belt-and-suspenders — the per-call duration is the primary control.
         * Success toasts auto-dismiss after the default 5 seconds.
         */}
        <Toaster
          position="bottom-right"
          richColors
          toastOptions={{
            classNames: { error: "!duration-[Infinity]" },
          }}
        />
      </body>
    </html>
  );
}
