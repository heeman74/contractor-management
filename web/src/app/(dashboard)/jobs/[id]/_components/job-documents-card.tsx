import { useRouter } from "next/navigation";
import type { Job, Quote, Invoice } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { jobHasDocuments } from "../_lib/job-transitions";

interface JobDocumentsCardProps {
  job: Job;
  existingQuote: Quote | null | undefined;
  existingInvoice: Invoice | null | undefined;
  isGeneratingInvoice: boolean;
  onGenerateInvoice: () => void;
}

export function JobDocumentsCard({
  job,
  existingQuote,
  existingInvoice,
  isGeneratingInvoice,
  onGenerateInvoice,
}: JobDocumentsCardProps) {
  const router = useRouter();

  if (!jobHasDocuments(job)) return null;

  const quoteButton = existingQuote ? (
    <Button
      size="sm"
      variant="outline"
      className="w-full"
      onClick={() => router.push(`/quotes/${existingQuote.id}`)}
    >
      View Quote
    </Button>
  ) : null;

  const invoiceButton = existingInvoice ? (
    <Button
      size="sm"
      variant="outline"
      className="w-full"
      onClick={() => router.push(`/invoices/${existingInvoice.id}`)}
    >
      View Invoice
    </Button>
  ) : null;

  return (
    <Card>
      <CardHeader>
        <CardTitle>Documents</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {job.status === "quote" &&
          (quoteButton ?? (
            <Button
              size="sm"
              className="w-full"
              onClick={() => router.push(`/quotes/new/edit?job_id=${job.id}`)}
            >
              Create Quote
            </Button>
          ))}

        {job.status === "complete" &&
          (invoiceButton ??
            (existingQuote?.status === "approved" ? (
              <Button
                size="sm"
                className="w-full"
                onClick={onGenerateInvoice}
                disabled={isGeneratingInvoice}
              >
                {isGeneratingInvoice ? "Generating..." : "Generate Invoice"}
              </Button>
            ) : (
              <p className="text-xs text-gray-400">
                An approved quote is required to generate an invoice.
              </p>
            )))}

        {job.status === "invoiced" && (
          <div className="space-y-2">
            {quoteButton}
            {invoiceButton}
          </div>
        )}
      </CardContent>
    </Card>
  );
}
