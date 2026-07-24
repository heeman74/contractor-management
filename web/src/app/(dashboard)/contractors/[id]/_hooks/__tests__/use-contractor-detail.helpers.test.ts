import type { ContractorListItem, Job, WeeklyBlock } from "@/types/api";
import {
  ACTIVE_JOB_STATUSES,
  blockDurationMinutes,
  calcHoursThisWeek,
  getInitials,
  getMostCommonTradeType,
  hasWorkingHours,
} from "../use-contractor-detail";

function job(overrides: Partial<Job> = {}): Job {
  return { trade_type: "plumbing", status: "scheduled", ...overrides } as Job;
}

function block(start: string, end: string): WeeklyBlock {
  return { start_time: start, end_time: end } as WeeklyBlock;
}

function contractor(overrides: Partial<ContractorListItem> = {}): ContractorListItem {
  return { first_name: "John", last_name: "Doe", ...overrides } as ContractorListItem;
}

describe("ACTIVE_JOB_STATUSES", () => {
  test("counts scheduled and in-progress work as active", () => {
    expect(ACTIVE_JOB_STATUSES).toEqual(["scheduled", "in_progress"]);
  });
});

describe("getMostCommonTradeType", () => {
  test("returns null for an empty job list", () => {
    expect(getMostCommonTradeType([])).toBeNull();
  });

  test("returns null when no job carries a trade type", () => {
    expect(getMostCommonTradeType([job({ trade_type: undefined })])).toBeNull();
  });

  test("returns the most frequent trade type", () => {
    const jobs = [
      job({ trade_type: "plumbing" }),
      job({ trade_type: "electrical" }),
      job({ trade_type: "plumbing" }),
    ];
    expect(getMostCommonTradeType(jobs)).toBe("plumbing");
  });
});

describe("blockDurationMinutes", () => {
  test("computes the minute span of a block", () => {
    expect(blockDurationMinutes(block("09:00", "17:30"))).toBe(510);
  });

  test("clamps inverted ranges to zero", () => {
    expect(blockDurationMinutes(block("17:00", "09:00"))).toBe(0);
  });
});

describe("calcHoursThisWeek", () => {
  test("returns 0 when there is no schedule", () => {
    expect(calcHoursThisWeek(undefined)).toBe(0);
  });

  test("sums every block across days and rounds to one decimal", () => {
    const schedule: Record<string, WeeklyBlock[]> = {
      monday: [block("08:00", "12:00"), block("13:00", "17:00")], // 8h
      tuesday: [block("09:00", "09:45")], // 0.75h → 0.8
    };
    expect(calcHoursThisWeek(schedule)).toBe(8.8);
  });
});

describe("getInitials", () => {
  test("uppercases the first letter of each name", () => {
    expect(getInitials(contractor({ first_name: "ada", last_name: "byron" }))).toBe("AB");
  });

  test("falls back to ? when the contractor is missing", () => {
    expect(getInitials(undefined)).toBe("?");
  });
});

describe("hasWorkingHours", () => {
  test("is false for an undefined or all-empty schedule", () => {
    expect(hasWorkingHours(undefined)).toBe(false);
    expect(hasWorkingHours({ monday: [], tuesday: [] })).toBe(false);
  });

  test("is true when any day has a block", () => {
    expect(hasWorkingHours({ monday: [], friday: [block("09:00", "10:00")] })).toBe(true);
  });
});
