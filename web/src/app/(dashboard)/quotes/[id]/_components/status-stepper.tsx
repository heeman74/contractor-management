import { formatStatus } from "@/lib/format";
import { QUOTE_STEPPER_STEPS } from "../_lib/quote-activity";

const BASE_PILL = "rounded-full px-2 py-0.5 text-xs";
const DONE_PILL = `${BASE_PILL} bg-primary text-white`;
const CURRENT_PILL = `${BASE_PILL} bg-secondary text-foreground font-semibold`;
const PENDING_PILL = `${BASE_PILL} bg-gray-100 text-gray-400`;

// "approved" is the final happy-path step; a declined/expired quote reached
// every step before it but never got approved.
const APPROVED_STEP_INDEX = QUOTE_STEPPER_STEPS.indexOf("approved");

function stepPillClass(
  index: number,
  currentIndex: number,
  isTerminal: boolean
): string {
  if (isTerminal) {
    return index < APPROVED_STEP_INDEX ? DONE_PILL : PENDING_PILL;
  }
  if (index < currentIndex) return DONE_PILL;
  if (index === currentIndex) return CURRENT_PILL;
  return PENDING_PILL;
}

export function StatusStepper({ currentStatus }: { currentStatus: string }) {
  const currentIndex = QUOTE_STEPPER_STEPS.indexOf(currentStatus);
  const isTerminal =
    currentStatus === "declined" || currentStatus === "expired";

  return (
    <div className="flex items-center flex-wrap gap-1">
      {QUOTE_STEPPER_STEPS.map((step, index) => (
        <span key={step} className="flex items-center">
          <span className={stepPillClass(index, currentIndex, isTerminal)}>
            {formatStatus(step)}
          </span>
          {index < QUOTE_STEPPER_STEPS.length - 1 && (
            <span className="text-xs text-gray-300 mx-1">→</span>
          )}
        </span>
      ))}
      {isTerminal && (
        <>
          <span className="text-xs text-gray-300 mx-1">/</span>
          <span className={CURRENT_PILL}>{formatStatus(currentStatus)}</span>
        </>
      )}
    </div>
  );
}
