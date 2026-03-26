"""Request-scoped trace context for correlating logs across a request lifecycle.

Uses ContextVar so each async request gets isolated context.
Middleware sets it; loggers read it automatically via structlog processor.
"""

from __future__ import annotations

from contextvars import ContextVar
from typing import Any

_trace_context: ContextVar[dict[str, Any] | None] = ContextVar(
    "trace_context", default=None
)


def set_trace_context(
    *,
    request_id: str,
    method: str = "",
    path: str = "",
    start_time: float = 0.0,
    user_id: str | None = None,
    company_id: str | None = None,
) -> None:
    """Set the trace context for the current request."""
    _trace_context.set(
        {
            "request_id": request_id,
            "method": method,
            "path": path,
            "start_time": start_time,
            "user_id": user_id,
            "company_id": company_id,
        }
    )


def get_trace_context() -> dict[str, Any]:
    """Return the current request's trace context (empty dict if unset)."""
    return _trace_context.get() or {}


def update_trace_context(**kwargs: Any) -> None:
    """Merge additional fields into the current trace context.

    Useful for adding user_id/company_id after JWT validation, which happens
    after the middleware has already set the initial trace context.
    """
    ctx = _trace_context.get()
    if ctx:
        ctx.update(kwargs)
        _trace_context.set(ctx)


def clear_trace_context() -> None:
    """Reset trace context to None (called at end of request)."""
    _trace_context.set(None)


def inject_trace_context(
    logger: Any, method_name: str, event_dict: dict[str, Any]
) -> dict[str, Any]:
    """Structlog processor that merges trace context into every log entry.

    Adds request_id, user_id, and company_id from the current ContextVar
    into the log event dict. Skips fields that are None or empty.
    """
    ctx = get_trace_context()
    if ctx:
        for key in ("request_id", "user_id", "company_id"):
            value = ctx.get(key)
            if value is not None:
                event_dict[key] = value
    return event_dict
