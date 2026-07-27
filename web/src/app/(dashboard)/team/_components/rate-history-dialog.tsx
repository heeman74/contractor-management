"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { useAddLaborRate, useLaborRateHistory } from "@/features/finance/hooks";
import type { LaborRate } from "@/features/finance/types";
import { formatCurrency, formatDate } from "@/lib/format";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

const MONTH_LABELS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

const AMOUNT_VALIDATION_MESSAGE = "Enter an hourly rate greater than $0.";
const DATE_VALIDATION_MESSAGE = "Choose an effective date.";
const SAVE_ERROR_MESSAGE = "Could not save rate. Please try again.";
const HISTORY_ERROR_MESSAGE = "Failed to load rate history. Please try again.";

/** "2026-05-01" -> "May 1, 2026" without Date() timezone shifting. */
function formatEffectiveDate(isoDate: string): string {
  const [year, month, day] = isoDate.split("-").map(Number);
  return `${MONTH_LABELS[month - 1]} ${day}, ${year}`;
}

function todayIsoDate(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * The currently-effective rate: greatest effectiveFrom <= today, ties broken
 * by latest createdAt — the same rule the backend applies in
 * backend/app/features/finance/labor_derivation.py.
 */
export function currentRate(rates: LaborRate[], today: string): LaborRate | null {
  const effective = rates.filter((rate) => rate.effectiveFrom <= today);
  if (effective.length === 0) return null;
  return effective.reduce((winner, rate) => {
    if (rate.effectiveFrom !== winner.effectiveFrom) {
      return rate.effectiveFrom > winner.effectiveFrom ? rate : winner;
    }
    return rate.createdAt > winner.createdAt ? rate : winner;
  });
}

/** The soonest future-dated rate, or null when none is scheduled. */
export function nextFutureRate(rates: LaborRate[], today: string): LaborRate | null {
  const future = rates.filter((rate) => rate.effectiveFrom > today);
  if (future.length === 0) return null;
  return future.reduce((winner, rate) =>
    rate.effectiveFrom < winner.effectiveFrom ? rate : winner
  );
}

/** Rows sharing an effectiveFrom with a later-created row (latest createdAt wins). */
export function supersededRateIds(rates: LaborRate[]): Set<string> {
  const superseded = new Set<string>();
  for (const rate of rates) {
    const hasNewerSameDay = rates.some(
      (other) =>
        other.id !== rate.id &&
        other.effectiveFrom === rate.effectiveFrom &&
        other.createdAt > rate.createdAt
    );
    if (hasNewerSameDay) superseded.add(rate.id);
  }
  return superseded;
}

function sortHistory(rates: LaborRate[]): LaborRate[] {
  return [...rates].sort(
    (a, b) =>
      b.effectiveFrom.localeCompare(a.effectiveFrom) ||
      b.createdAt.localeCompare(a.createdAt)
  );
}

interface RateHistoryDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  userId: string;
  memberName: string;
}

export function RateHistoryDialog({
  open,
  onOpenChange,
  userId,
  memberName,
}: RateHistoryDialogProps) {
  const [amount, setAmount] = useState("");
  const [effectiveFrom, setEffectiveFrom] = useState(todayIsoDate);
  const [formError, setFormError] = useState<string | null>(null);

  const { data: rates, isError } = useLaborRateHistory(userId, open);
  const addRate = useAddLaborRate();

  useEffect(() => {
    if (isError) toast.error(HISTORY_ERROR_MESSAGE);
  }, [isError]);

  const handleOpenChange = (nextOpen: boolean) => {
    if (!nextOpen) {
      setAmount("");
      setEffectiveFrom(todayIsoDate());
      setFormError(null);
    }
    onOpenChange(nextOpen);
  };

  const today = todayIsoDate();
  const history = rates ?? [];
  const current = currentRate(history, today);
  const upcoming = nextFutureRate(history, today);

  const handleSubmit = (event: React.FormEvent) => {
    event.preventDefault();
    const parsedAmount = Number(amount);
    if (!amount.trim() || Number.isNaN(parsedAmount) || parsedAmount <= 0) {
      return setFormError(AMOUNT_VALIDATION_MESSAGE);
    }
    if (!effectiveFrom) return setFormError(DATE_VALIDATION_MESSAGE);
    setFormError(null);

    addRate.mutate(
      { userId, hourlyCost: amount, effectiveFrom },
      {
        onSuccess: () => {
          toast.success(
            `Rate added — effective ${formatEffectiveDate(effectiveFrom)}.`
          );
          setAmount("");
        },
        onError: () => toast.error(SAVE_ERROR_MESSAGE),
      }
    );
  };

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="text-xl font-semibold text-gray-900">
            Labor rate — {memberName}
          </DialogTitle>
        </DialogHeader>

        <CurrentRateHeadline current={current} upcoming={upcoming} />

        <form onSubmit={handleSubmit} className="space-y-3">
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="grid content-start gap-2">
              <Label htmlFor="rate-amount">Hourly rate</Label>
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm text-gray-500">
                  $
                </span>
                <Input
                  id="rate-amount"
                  type="text"
                  inputMode="decimal"
                  className="pl-7"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                />
              </div>
            </div>
            <div className="grid content-start gap-2">
              <Label htmlFor="rate-effective-date">Effective date</Label>
              <Input
                id="rate-effective-date"
                type="date"
                value={effectiveFrom}
                onChange={(e) => setEffectiveFrom(e.target.value)}
              />
              <p className="text-xs text-gray-500">
                Backdating fills in unrated hours for past work days.
              </p>
            </div>
          </div>
          {formError && (
            <p className="text-sm text-destructive" role="alert">
              {formError}
            </p>
          )}
          <div className="flex justify-end">
            <Button type="submit" disabled={addRate.isPending}>
              Add Rate
            </Button>
          </div>
        </form>

        {history.length === 0 ? (
          <RateHistoryEmptyState />
        ) : (
          <RateHistoryTable rates={sortHistory(history)} today={today} />
        )}
      </DialogContent>
    </Dialog>
  );
}

function CurrentRateHeadline({
  current,
  upcoming,
}: {
  current: LaborRate | null;
  upcoming: LaborRate | null;
}) {
  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-wide text-gray-500">
        CURRENT RATE
      </p>
      <p
        className="text-2xl font-semibold text-gray-900"
        data-testid="current-rate-figure"
      >
        {current ? `${formatCurrency(current.hourlyCost)}/hr` : "—"}
      </p>
      {upcoming && (
        <p className="text-xs text-gray-500">
          Starts {formatEffectiveDate(upcoming.effectiveFrom)}:{" "}
          {formatCurrency(upcoming.hourlyCost)}/hr
        </p>
      )}
    </div>
  );
}

function RateHistoryEmptyState() {
  return (
    <div className="py-2">
      <p className="text-sm font-medium text-gray-900">No rate set yet</p>
      <p className="mt-1 text-sm text-gray-500">
        Hours this member tracks will show as unrated until you add a rate.
        Backdate the effective date to cover past work.
      </p>
    </div>
  );
}

function RateHistoryTable({ rates, today }: { rates: LaborRate[]; today: string }) {
  const supersededIds = supersededRateIds(rates);
  return (
    <Table>
      <TableHeader>
        <TableRow>
          {["Effective from", "Rate", "Added"].map((header) => (
            <TableHead
              key={header}
              className="text-xs font-semibold text-gray-500 uppercase tracking-wide"
            >
              {header}
            </TableHead>
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {rates.map((rate) => (
          <RateHistoryRow
            key={rate.id}
            rate={rate}
            isFuture={rate.effectiveFrom > today}
            isSuperseded={supersededIds.has(rate.id)}
          />
        ))}
      </TableBody>
    </Table>
  );
}

function RateHistoryRow({
  rate,
  isFuture,
  isSuperseded,
}: {
  rate: LaborRate;
  isFuture: boolean;
  isSuperseded: boolean;
}) {
  return (
    <TableRow
      data-testid={`rate-row-${rate.id}`}
      className={isSuperseded ? "text-gray-400" : undefined}
    >
      <TableCell className="py-3 px-4 text-sm">
        <div className="flex items-center gap-2">
          <span>{formatEffectiveDate(rate.effectiveFrom)}</span>
          {isFuture && (
            <Badge className="bg-gray-100 text-gray-700 border-0">
              Starts {formatEffectiveDate(rate.effectiveFrom)}
            </Badge>
          )}
          {isSuperseded && (
            <Badge className="bg-gray-100 text-gray-700 border-0">Superseded</Badge>
          )}
        </div>
      </TableCell>
      <TableCell className="py-3 px-4 text-sm">
        {formatCurrency(rate.hourlyCost)}/hr
      </TableCell>
      <TableCell className="py-3 px-4 text-sm">{formatDate(rate.createdAt)}</TableCell>
    </TableRow>
  );
}
