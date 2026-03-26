"""Structured logging configuration using structlog.

- Development: colored, human-readable console output
- Production: JSON lines for log aggregation (ELK, CloudWatch, etc.)

Log levels controlled via LOG_LEVEL env var (default: INFO).
Request context (request_id, user_id, company_id) automatically attached via ContextVar.
"""

from __future__ import annotations

import logging
import os
import sys

import structlog

from app.core.trace_context import inject_trace_context


def setup_logging(env: str | None = None) -> None:
    """Configure structlog and stdlib logging for the application.

    Args:
        env: Environment name. If None, reads from APP_ENV env var.
             "production" enables JSON output; anything else enables
             colored console output.
    """
    if env is None:
        env = os.environ.get("APP_ENV", "development").lower()

    log_level_name = os.environ.get("LOG_LEVEL", "INFO").upper()
    log_level = getattr(logging, log_level_name, logging.INFO)

    is_production = env == "production"

    # Shared processors applied to every log entry
    shared_processors: list[structlog.types.Processor] = [
        structlog.contextvars.merge_contextvars,
        inject_trace_context,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.UnicodeDecoder(),
    ]

    if is_production:
        # Production: JSON lines for machine parsing
        renderer: structlog.types.Processor = structlog.processors.JSONRenderer()
    else:
        # Development: colored, human-readable console output
        renderer = structlog.dev.ConsoleRenderer(colors=True)

    # Configure structlog
    structlog.configure(
        processors=[
            *shared_processors,
            # Format exceptions as strings for the final renderer
            structlog.processors.format_exc_info,
            # Bridge to stdlib for final rendering
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    # Configure stdlib logging to use structlog formatting
    formatter = structlog.stdlib.ProcessorFormatter(
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            renderer,
        ],
        foreign_pre_chain=shared_processors,
    )

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(formatter)

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.handlers.clear()
    root_logger.addHandler(handler)
    root_logger.setLevel(log_level)

    # Quiet noisy third-party loggers
    for noisy_logger in ("uvicorn.access", "uvicorn.error", "asyncio", "apscheduler"):
        logging.getLogger(noisy_logger).setLevel(max(log_level, logging.WARNING))

    # Keep uvicorn's main logger at INFO so startup messages show
    logging.getLogger("uvicorn").setLevel(log_level)


def get_logger(name: str) -> structlog.stdlib.BoundLogger:
    """Return a bound structlog logger for the given module name.

    Usage:
        logger = get_logger(__name__)
        logger.info("something happened", key="value")
    """
    return structlog.get_logger(name)
