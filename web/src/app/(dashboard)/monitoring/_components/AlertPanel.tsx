"use client";

import { useEffect, useRef, useMemo, useCallback, memo } from "react";
import { Info, AlertTriangle, AlertOctagon, CheckCircle2 } from "lucide-react";
import {
  useDashboardAlerts,
  useMarkAlertRead,
  useAcceptRescheduling,
  useDismissAlert,
} from "@/lib/hooks/useDashboard";
import type { DashboardAlert } from "@/lib/types/dashboard";

const MARK_READ_DEBOUNCE_MS = 300;
const VISIBILITY_THRESHOLD = 0.5;
const ALERT_TYPE_RESCHEDULING = "rescheduling_suggestion";

interface AlertPanelProps {
  projectId?: string;
}

// Severity icon config
const severityConfig = {
  info: {
    Icon: Info,
    iconClass: "text-blue-500",
    borderClass: "border-l-blue-400",
  },
  warning: {
    Icon: AlertTriangle,
    iconClass: "text-amber-500",
    borderClass: "border-l-amber-400",
  },
  critical: {
    Icon: AlertOctagon,
    iconClass: "text-red-500",
    borderClass: "border-l-red-400",
  },
} as const;

interface AlertCardProps {
  alert: DashboardAlert;
  onMarkRead: (alertId: string) => void;
  onAcceptRescheduling: (alertId: string) => void;
  onDismiss: (alertId: string) => void;
  acceptingAlertId: string | null;
  dismissingAlertId: string | null;
}

const AlertCard = memo(function AlertCard({
  alert,
  onMarkRead,
  onAcceptRescheduling,
  onDismiss,
  acceptingAlertId,
  dismissingAlertId,
}: AlertCardProps) {
  const isAccepting = acceptingAlertId === alert.id;
  const isDismissing = dismissingAlertId === alert.id;
  const cardRef = useRef<HTMLDivElement>(null);

  // Use a ref for the mark-read callback to avoid re-creating the observer
  const onMarkReadRef = useRef(onMarkRead);
  useEffect(() => {
    onMarkReadRef.current = onMarkRead;
  });

  // Mark as read when card scrolls into view (batched via parent)
  useEffect(() => {
    if (alert.is_read) return;
    const el = cardRef.current;
    if (!el) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) {
          onMarkReadRef.current(alert.id);
          observer.disconnect();
        }
      },
      { threshold: VISIBILITY_THRESHOLD }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [alert.id, alert.is_read]);

  const config =
    severityConfig[alert.severity] ?? severityConfig.info;
  const { Icon, iconClass, borderClass } = config;

  const isPendingRescheduling =
    alert.alert_type === ALERT_TYPE_RESCHEDULING &&
    alert.rescheduling_accepted === null;

  return (
    <div
      ref={cardRef}
      className={`rounded-lg border border-gray-200 border-l-4 ${borderClass} bg-white p-3 shadow-sm ${
        !alert.is_read ? "bg-secondary/30" : ""
      }`}
    >
      <div className="flex items-start gap-2">
        <Icon
          className={`mt-0.5 h-4 w-4 flex-shrink-0 ${iconClass}`}
          aria-label={`${alert.severity} severity`}
        />
        <div className="flex-1 min-w-0">
          {/* Impact text */}
          <p className="text-xs font-medium text-gray-900 leading-snug">
            {alert.impact_text}
          </p>

          {/* Days behind */}
          {alert.days_behind !== null && alert.days_behind > 0 && (
            <p className="mt-0.5 text-xs text-red-600">
              {alert.days_behind} day{alert.days_behind !== 1 ? "s" : ""} behind schedule
            </p>
          )}

          {/* Remediation text */}
          {alert.remediation_text && (
            <p className="mt-1 text-xs italic text-gray-500 leading-snug">
              {alert.remediation_text}
            </p>
          )}

          {/* Rescheduling action buttons */}
          {isPendingRescheduling && (
            <div className="mt-2 flex gap-2">
              <button
                onClick={() => onAcceptRescheduling(alert.id)}
                disabled={isAccepting}
                className="rounded-md bg-primary px-2.5 py-1 text-xs font-medium text-white hover:bg-primary/90 disabled:opacity-50 transition-colors"
              >
                {isAccepting ? "Applying..." : "Accept Rescheduling"}
              </button>
              <button
                onClick={() => onDismiss(alert.id)}
                disabled={isDismissing}
                className="rounded-md border border-gray-300 px-2.5 py-1 text-xs font-medium text-gray-600 hover:bg-gray-50 disabled:opacity-50 transition-colors"
              >
                Dismiss
              </button>
            </div>
          )}

          {/* Applied state */}
          {alert.rescheduling_accepted === true && (
            <div className="mt-2 flex items-center gap-1 text-xs text-green-600 font-medium">
              <CheckCircle2 className="h-3.5 w-3.5" />
              <span>Applied</span>
            </div>
          )}

          {/* Dismissed state */}
          {alert.rescheduling_accepted === false && (
            <p className="mt-1 text-xs text-gray-400">Dismissed</p>
          )}
        </div>
      </div>
    </div>
  );
});

export function AlertPanel({ projectId }: AlertPanelProps) {
  const { data: alerts, isLoading, isError } = useDashboardAlerts(projectId);

  const markRead = useMarkAlertRead();
  const acceptRescheduling = useAcceptRescheduling();
  const dismissAlert = useDismissAlert();

  // Use refs for all mutation functions to keep callbacks stable across renders
  const markReadMutateRef = useRef(markRead.mutate);
  const acceptMutateRef = useRef(acceptRescheduling.mutate);
  const dismissMutateRef = useRef(dismissAlert.mutate);
  useEffect(() => {
    markReadMutateRef.current = markRead.mutate;
    acceptMutateRef.current = acceptRescheduling.mutate;
    dismissMutateRef.current = dismissAlert.mutate;
  });

  // Batch mark-as-read with debounce to avoid flooding the server
  const pendingMarkReadIds = useRef<Set<string>>(new Set());
  const batchTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const flushMarkRead = useCallback(() => {
    const ids = Array.from(pendingMarkReadIds.current);
    pendingMarkReadIds.current.clear();
    for (const id of ids) {
      markReadMutateRef.current(id);
    }
  }, []);

  const handleMarkRead = useCallback(
    (alertId: string) => {
      pendingMarkReadIds.current.add(alertId);
      if (batchTimerRef.current) clearTimeout(batchTimerRef.current);
      batchTimerRef.current = setTimeout(flushMarkRead, MARK_READ_DEBOUNCE_MS);
    },
    [flushMarkRead]
  );

  // Cleanup batch timer on unmount
  useEffect(() => {
    return () => {
      if (batchTimerRef.current) clearTimeout(batchTimerRef.current);
    };
  }, []);

  // Clear stale pending IDs when switching projects
  useEffect(() => {
    pendingMarkReadIds.current.clear();
    if (batchTimerRef.current) clearTimeout(batchTimerRef.current);
  }, [projectId]);

  const handleAccept = useCallback(
    (alertId: string) => acceptMutateRef.current(alertId),
    []
  );

  const handleDismiss = useCallback(
    (alertId: string) => dismissMutateRef.current(alertId),
    []
  );

  const unreadCount = useMemo(
    () => alerts?.filter((alert) => !alert.is_read).length ?? 0,
    [alerts]
  );

  return (
    <div className="rounded-xl border border-gray-200 bg-white shadow-sm overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-gray-100 px-4 py-3">
        <h2 className="text-sm font-semibold text-gray-900">Alerts</h2>
        {unreadCount > 0 && (
          <span className="inline-flex items-center rounded-full bg-primary px-2 py-0.5 text-xs font-medium text-white">
            {unreadCount} new
          </span>
        )}
      </div>

      {/* Alert list */}
      <div className="max-h-[600px] overflow-y-auto p-3 space-y-2">
        {isLoading ? (
          <>
            {[...Array(3)].map((_, i) => (
              <div key={i} className="h-20 animate-pulse rounded-lg bg-gray-100" />
            ))}
          </>
        ) : isError ? (
          <p className="py-4 text-center text-xs text-red-500">
            Failed to load alerts.
          </p>
        ) : !alerts || alerts.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-8 text-center">
            <CheckCircle2 className="h-8 w-8 text-green-400" />
            <p className="text-sm text-gray-500">
              No alerts — all projects on track
            </p>
          </div>
        ) : (
          alerts.map((alert) => (
            <AlertCard
              key={alert.id}
              alert={alert}
              onMarkRead={handleMarkRead}
              onAcceptRescheduling={handleAccept}
              onDismiss={handleDismiss}
              acceptingAlertId={acceptRescheduling.isPending ? (acceptRescheduling.variables ?? null) : null}
              dismissingAlertId={dismissAlert.isPending ? (dismissAlert.variables ?? null) : null}
            />
          ))
        )}
      </div>
    </div>
  );
}
