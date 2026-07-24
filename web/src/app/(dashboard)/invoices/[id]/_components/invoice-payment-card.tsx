import { useState } from "react";
import type { Invoice } from "@/types/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { PaymentSummary } from "./payment-summary";

interface InvoicePaymentCardProps {
  invoice: Invoice;
  balance: number;
  isOverdue: boolean;
  isPaid: boolean;
  isRecordingPayment: boolean;
  /** Form visibility is lifted so the sidebar "Record Payment" action can open it too. */
  showForm: boolean;
  onShowFormChange: (show: boolean) => void;
  /** Records the payment; returns a validation error message, or null on success. */
  onRecordPayment: (amount: string) => string | null;
}

export function InvoicePaymentCard({
  invoice,
  balance,
  isOverdue,
  isPaid,
  isRecordingPayment,
  showForm,
  onShowFormChange,
  onRecordPayment,
}: InvoicePaymentCardProps) {
  const [amount, setAmount] = useState("");
  const [error, setError] = useState<string | null>(null);

  function reset() {
    onShowFormChange(false);
    setAmount("");
    setError(null);
  }

  function submit() {
    const validationError = onRecordPayment(amount);
    if (validationError) {
      setError(validationError);
      return;
    }
    reset();
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Payment</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <PaymentSummary
          invoice={invoice}
          balance={balance}
          isOverdue={isOverdue}
          layout="inline"
        />

        {!isPaid &&
          (!showForm ? (
            <Button
              variant="outline"
              size="sm"
              onClick={() => onShowFormChange(true)}
            >
              Record Payment
            </Button>
          ) : (
            <div className="space-y-3 border rounded-lg p-3 bg-gray-50">
              <p className="text-xs font-semibold text-gray-700">Record Payment</p>
              <div className="flex items-center gap-2">
                <span className="text-sm text-gray-600 w-6 shrink-0">$</span>
                <Input
                  type="number"
                  step="0.01"
                  min="0.01"
                  max={balance}
                  placeholder="0.00"
                  value={amount}
                  onChange={(e) => {
                    setAmount(e.target.value);
                    setError(null);
                  }}
                  className="h-8 text-sm w-24"
                />
              </div>
              {error && <p className="text-xs text-red-600">{error}</p>}
              <div className="flex gap-2">
                <Button size="sm" onClick={submit} disabled={isRecordingPayment}>
                  Save Payment
                </Button>
                <Button variant="ghost" size="sm" onClick={reset}>
                  Cancel
                </Button>
              </div>
            </div>
          ))}
      </CardContent>
    </Card>
  );
}
