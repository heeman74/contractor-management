"""Throttling for failed login attempts.

Keyed on the account being attacked rather than on where the request came from.
Two reasons, both learned the hard way:

Counting every login request punished success. Someone who logged in once, left
for an hour and came back was refused — their own successful logins had spent
the budget, which protected nobody from anything. Only failures count here, and
a success clears the record.

Keying on the caller does not survive this architecture. Every browser request
reaches the API through the web app, so a caller-based key is one bucket for
everyone unless the browser's address is carried the whole way; when that
carrying breaks, every user in the world is locked out at once. The account
being guessed at is knowable from the request body and cannot collapse that way
— and it is what brute force actually targets.

In-process state, which matches the single worker the deployment runs. A restart
clears it, which is the right failure mode: it forgives rather than locks out.
"""

from __future__ import annotations

import threading
import time
from collections import defaultdict

# Enough room for a person who has genuinely forgotten which password they used,
# while leaving guessing hopeless: the space of real passwords is nowhere near
# this small.
MAX_FAILURES = 8

# How long failures are remembered, and so the longest anyone waits.
WINDOW_SECONDS = 300


class LoginThrottle:
    """Counts recent failed attempts per account."""

    def __init__(self, max_failures: int = MAX_FAILURES, window: int = WINDOW_SECONDS):
        self._max_failures = max_failures
        self._window = window
        self._failures: dict[str, list[float]] = defaultdict(list)
        # Touched from request handlers, which may be on different threads.
        self._lock = threading.Lock()

    @staticmethod
    def _key(email: str, caller: str = "") -> str:
        """Which account, as seen from which caller.

        Counting an account's failures regardless of who made them means a
        stranger failing against a known address locks its owner out — the
        throttle becomes a way to deny someone their own account. Pairing it
        with the caller keeps a guesser's failures to themselves.

        When the caller cannot be told apart — every browser reaches this API
        through the web app, so that happens — this collapses back to counting
        per account, which is where it started and no worse.
        """
        return f"{email.strip().lower()}|{caller}"

    def _recent(self, key: str, now: float) -> list[float]:
        """Failures still inside the window, dropping the ones that aged out."""
        kept = [at for at in self._failures[key] if now - at < self._window]
        if kept:
            self._failures[key] = kept
        else:
            self._failures.pop(key, None)
        return kept

    def retry_after(self, email: str, caller: str = "") -> int | None:
        """Seconds to wait, or None when an attempt is allowed."""
        key = self._key(email, caller)
        now = time.monotonic()
        with self._lock:
            recent = self._recent(key, now)
            if len(recent) < self._max_failures:
                return None
            # Free again when the oldest failure in the window ages out.
            return max(1, int(self._window - (now - recent[0])))

    def record_failure(self, email: str, caller: str = "") -> None:
        key = self._key(email, caller)
        now = time.monotonic()
        with self._lock:
            self._recent(key, now)
            self._failures[key].append(now)

    def clear(self, email: str, caller: str = "") -> None:
        """Forget an account's failures — called when a password proves correct."""
        with self._lock:
            self._failures.pop(self._key(email, caller), None)

    def reset(self) -> None:
        """Drop all state. For tests, which must not inherit each other's."""
        with self._lock:
            self._failures.clear()


login_throttle = LoginThrottle()
