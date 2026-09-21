"""Minimal SSH client helpers built on asyncssh.

One connection per call -- these are on-demand ops/diagnostic calls, not a
high-frequency workload, so the simplicity of connect-per-call outweighs the
cost of a persistent connection pool.

NOTE on host key verification: known_hosts=None skips host key checking.
This is a deliberate tradeoff for an internal ops tool talking to a fixed,
small set of servers the user directly controls (not arbitrary internet
hosts) -- proper TOFU/pinning was judged not worth the added complexity for
this use case. If that changes, revisit before trusting this over a network
you don't control end to end.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import asyncssh

from .config import config

logger = logging.getLogger(__name__)


@dataclass
class CommandResult:
    exit_status: int
    stdout: str
    stderr: str

    @property
    def ok(self) -> bool:
        return self.exit_status == 0


async def _connect() -> asyncssh.SSHClientConnection:
    return await asyncssh.connect(
        config.host,
        port=config.port,
        username=config.user,
        client_keys=[config.key_path],
        known_hosts=None,
    )


async def run(command: str, timeout: float = 60.0) -> CommandResult:
    """Run a command over SSH and return its full output."""
    async with await _connect() as conn:
        result = await conn.run(command, check=False, timeout=timeout)
        return CommandResult(
            exit_status=result.exit_status if result.exit_status is not None else -1,
            stdout=result.stdout or "",
            stderr=result.stderr or "",
        )


async def run_streaming_to_file(command: str, local_path: str) -> tuple[int, int, str]:
    """
    Run a command over SSH and stream its stdout directly to a local file,
    without buffering the full output in memory. Used for database dumps,
    which can be large.

    Returns (exit_status, bytes_written, stderr_text).
    """
    async with await _connect() as conn:
        # encoding=None: stdout is binary (gzip-compressed dump), not text --
        # asyncssh defaults to UTF-8 decoding, which breaks on the first
        # non-UTF-8 byte in the gzip stream.
        async with conn.create_process(command, encoding=None) as process:
            bytes_written = 0
            with open(local_path, "wb") as f:
                while True:
                    chunk = await process.stdout.read(65536)
                    if not chunk:
                        break
                    f.write(chunk)
                    bytes_written += len(chunk)
            stderr_text = await process.stderr.read()
            stderr_text = stderr_text.decode("utf-8", errors="replace") if isinstance(stderr_text, bytes) else stderr_text
            await process.wait()
            exit_status = process.exit_status if process.exit_status is not None else -1
            return exit_status, bytes_written, stderr_text
