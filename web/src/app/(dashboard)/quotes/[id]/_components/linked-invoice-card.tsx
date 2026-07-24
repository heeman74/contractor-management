import Link from "next/link";
import type { Invoice } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatCurrency } from "@/lib/format";

export function LinkedInvoiceCard({ invoice }: { invoice: Invoice }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Linked Invoice</CardTitle>
      </CardHeader>
      <CardContent>
        <Link
          href={`/invoices/${invoice.id}`}
          className="text-sm text-foreground hover:underline block mb-1"
        >
          Invoice #{invoice.invoice_number}
        </Link>
        <div className="flex items-center justify-between">
          <span className="font-mono text-sm text-gray-900">
            {formatCurrency(invoice.total)}
          </span>
          <StatusBadge status={invoice.status} size="sm" />
        </div>
      </CardContent>
    </Card>
  );
}
