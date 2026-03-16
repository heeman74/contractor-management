import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { StoreProvider } from "@/store/provider";
import { QueryProvider } from "@/components/providers/query-provider";
import { Toaster } from "@/components/ui/sonner";
import NextTopLoader from "nextjs-toploader";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
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
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        {/* NProgress-style thin progress bar for route transitions */}
        <NextTopLoader color="#4f46e5" showSpinner={false} />
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
