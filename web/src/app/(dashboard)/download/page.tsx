"use client";

import { useState } from "react";
import { Smartphone, Apple, Download, QrCode, CheckCircle2, Copy } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

const APP_VERSION = "1.0.0";
const APK_FILENAME = "contractorhub.apk";
const APK_DOWNLOAD_PATH = "/api/download/apk";

function AndroidIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor">
      <path d="M17.523 2.27a.667.667 0 00-1.157.667l1.06 1.837A8.026 8.026 0 0012 3.667a8.026 8.026 0 00-5.426 1.107L7.634 2.937a.667.667 0 00-1.157-.667l-1.09 1.89A7.98 7.98 0 004 8.667h16a7.98 7.98 0 00-1.387-4.507l-1.09-1.89zM9.333 7a.667.667 0 110-1.333.667.667 0 010 1.333zm5.334 0a.667.667 0 110-1.333.667.667 0 010 1.333zM4 9.333v8A2.667 2.667 0 006.667 20h.666v2.667a1.333 1.333 0 002.667 0V20h4v2.667a1.333 1.333 0 002.667 0V20h.666A2.667 2.667 0 0020 17.333v-8H4zm-2.667 0a1.333 1.333 0 00-1.333 1.334v5.333a1.333 1.333 0 002.667 0v-5.333A1.333 1.333 0 001.333 9.333zm21.334 0a1.333 1.333 0 00-1.334 1.334v5.333a1.333 1.333 0 002.667 0v-5.333a1.333 1.333 0 00-1.333-1.334z" />
    </svg>
  );
}

export default function DownloadPage() {
  const [copied, setCopied] = useState(false);

  const testFlightUrl = "https://testflight.apple.com/join/YOUR_CODE";

  const handleCopyLink = async () => {
    const apkUrl = `${window.location.origin}${APK_DOWNLOAD_PATH}`;
    await navigator.clipboard.writeText(apkUrl);
    setCopied(true);
    toast.success("Download link copied!");
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="mx-auto max-w-3xl space-y-8">
      {/* Header */}
      <div className="text-center">
        <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-blue-600 text-white">
          <Smartphone className="h-8 w-8" />
        </div>
        <h1 className="text-2xl font-bold text-gray-900">Get ContractorHub Mobile</h1>
        <p className="mt-2 text-sm text-gray-500">
          Download the mobile app for field access — clock in/out, GPS capture,
          daily checklists, and offline sync.
        </p>
        <Badge variant="secondary" className="mt-3">
          Version {APP_VERSION}
        </Badge>
      </div>

      {/* Download Cards */}
      <div className="grid gap-6 md:grid-cols-2">
        {/* Android Card */}
        <Card className="relative overflow-hidden">
          <div className="absolute right-0 top-0 h-24 w-24 translate-x-6 -translate-y-6 rounded-full bg-green-50" />
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-green-100">
                <AndroidIcon className="h-5 w-5 text-green-700" />
              </div>
              <div>
                <CardTitle className="text-lg">Android</CardTitle>
                <CardDescription>Direct APK download</CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="rounded-lg bg-gray-50 p-3 text-xs text-gray-600 space-y-1">
              <p className="font-medium text-gray-700">Installation steps:</p>
              <ol className="list-decimal pl-4 space-y-0.5">
                <li>Tap Download APK below</li>
                <li>Open the downloaded file</li>
                <li>Allow &quot;Install from unknown sources&quot; if prompted</li>
                <li>Tap Install</li>
              </ol>
            </div>

            <a
              href={APK_DOWNLOAD_PATH}
              download={APK_FILENAME}
              className="inline-flex w-full items-center justify-center rounded-md bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700"
            >
              <Download className="mr-2 h-4 w-4" />
              Download APK
            </a>

            <Button
              variant="outline"
              size="sm"
              className="w-full"
              onClick={handleCopyLink}
            >
              {copied ? (
                <CheckCircle2 className="mr-2 h-4 w-4 text-green-600" />
              ) : (
                <Copy className="mr-2 h-4 w-4" />
              )}
              {copied ? "Copied!" : "Copy download link"}
            </Button>
          </CardContent>
        </Card>

        {/* iOS Card */}
        <Card className="relative overflow-hidden">
          <div className="absolute right-0 top-0 h-24 w-24 translate-x-6 -translate-y-6 rounded-full bg-blue-50" />
          <CardHeader>
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-blue-100">
                <Apple className="h-5 w-5 text-blue-700" />
              </div>
              <div>
                <CardTitle className="text-lg">iOS</CardTitle>
                <CardDescription>TestFlight beta</CardDescription>
              </div>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="rounded-lg bg-gray-50 p-3 text-xs text-gray-600 space-y-1">
              <p className="font-medium text-gray-700">Installation steps:</p>
              <ol className="list-decimal pl-4 space-y-0.5">
                <li>Install TestFlight from the App Store</li>
                <li>Tap the TestFlight link below</li>
                <li>Accept the invitation</li>
                <li>Install ContractorHub from TestFlight</li>
              </ol>
            </div>

            <a
              href={testFlightUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex w-full items-center justify-center rounded-md bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700"
            >
              <Apple className="mr-2 h-4 w-4" />
              Open TestFlight
            </a>

            <p className="text-center text-xs text-gray-400">
              Requires TestFlight app from the App Store
            </p>
          </CardContent>
        </Card>
      </div>

      {/* QR Code Section */}
      <Card>
        <CardHeader className="text-center">
          <CardTitle className="flex items-center justify-center gap-2 text-base">
            <QrCode className="h-5 w-5" />
            Share with your team
          </CardTitle>
          <CardDescription>
            Share the download page link with contractors and team members
          </CardDescription>
        </CardHeader>
        <CardContent className="text-center">
          <Button
            variant="outline"
            onClick={() => {
              const url = `${window.location.origin}/download`;
              navigator.clipboard.writeText(url);
              toast.success("Page link copied!");
            }}
          >
            <Copy className="mr-2 h-4 w-4" />
            Copy page link
          </Button>
        </CardContent>
      </Card>

      {/* Features */}
      <div className="rounded-xl bg-gray-50 p-6">
        <h3 className="mb-4 text-sm font-semibold text-gray-700">Mobile app features</h3>
        <div className="grid gap-3 sm:grid-cols-2">
          {[
            "Clock in/out with GPS",
            "Daily AI checklists",
            "Photo capture & annotations",
            "Offline mode with sync",
            "Job status updates",
            "Real-time chat",
            "Schedule & calendar view",
            "Push notifications",
          ].map((feature) => (
            <div key={feature} className="flex items-center gap-2 text-sm text-gray-600">
              <CheckCircle2 className="h-4 w-4 shrink-0 text-green-500" />
              {feature}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
