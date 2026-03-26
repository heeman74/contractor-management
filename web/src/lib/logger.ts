/**
 * Structured logger for ContractorHub web app.
 *
 * - Development: colored console output with context
 * - Production: JSON lines (for log aggregation if stdout is captured)
 * - Levels: debug, info, warn, error
 * - Automatic context: timestamp, level, component tag
 * - Request ID tracking for API call correlation
 */

export type LogLevel = "debug" | "info" | "warn" | "error";

export interface LogEntry {
  timestamp: string;
  level: LogLevel;
  tag: string;
  message: string;
  data?: Record<string, unknown>;
  requestId?: string;
}

const LOG_LEVEL_PRIORITY: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const LOG_LEVEL_COLORS: Record<LogLevel, string> = {
  debug: "\x1b[36m", // cyan
  info: "\x1b[32m",  // green
  warn: "\x1b[33m",  // yellow
  error: "\x1b[31m", // red
};

const RESET = "\x1b[0m";

class Logger {
  private _requestId: string | undefined;
  private _minLevel: LogLevel;

  constructor() {
    this._minLevel =
      process.env.NODE_ENV === "production" ? "info" : "debug";
  }

  /** Set request ID for correlation across API calls. */
  setRequestId(id: string): void {
    this._requestId = id;
  }

  /** Get current request ID. */
  getRequestId(): string | undefined {
    return this._requestId;
  }

  /** Clear request ID (e.g. at end of request lifecycle). */
  clearRequestId(): void {
    this._requestId = undefined;
  }

  debug(tag: string, message: string, data?: Record<string, unknown>): void {
    this._log("debug", tag, message, data);
  }

  info(tag: string, message: string, data?: Record<string, unknown>): void {
    this._log("info", tag, message, data);
  }

  warn(tag: string, message: string, data?: Record<string, unknown>): void {
    this._log("warn", tag, message, data);
  }

  error(tag: string, message: string, data?: Record<string, unknown>): void {
    this._log("error", tag, message, data);
  }

  private _log(
    level: LogLevel,
    tag: string,
    message: string,
    data?: Record<string, unknown>
  ): void {
    if (LOG_LEVEL_PRIORITY[level] < LOG_LEVEL_PRIORITY[this._minLevel]) {
      return;
    }

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level,
      tag,
      message,
      ...(data !== undefined && { data }),
      ...(this._requestId !== undefined && { requestId: this._requestId }),
    };

    if (process.env.NODE_ENV === "production") {
      this._logJson(level, entry);
    } else {
      this._logDev(level, entry);
    }
  }

  /** Production: single JSON line per log entry. */
  private _logJson(level: LogLevel, entry: LogEntry): void {
    const line = JSON.stringify(entry);
    switch (level) {
      case "debug":
      case "info":
        console.log(line);
        break;
      case "warn":
        console.warn(line);
        break;
      case "error":
        console.error(line);
        break;
    }
  }

  /** Development: formatted, colored console output. */
  private _logDev(level: LogLevel, entry: LogEntry): void {
    const color = LOG_LEVEL_COLORS[level];
    const lvl = level.toUpperCase().padEnd(5);
    const prefix = `${color}${lvl}${RESET} [${entry.tag}]`;
    const ridSuffix = entry.requestId ? ` rid=${entry.requestId}` : "";
    const formatted = `${entry.timestamp} ${prefix} ${entry.message}${ridSuffix}`;

    const consoleFn =
      level === "error"
        ? console.error
        : level === "warn"
          ? console.warn
          : console.log;

    if (entry.data) {
      consoleFn(formatted, entry.data);
    } else {
      consoleFn(formatted);
    }
  }
}

/** Singleton logger instance. */
export const logger = new Logger();
