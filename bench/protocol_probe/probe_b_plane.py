#!/usr/bin/env python3
"""Caduceus P0 Spike B — can a third-party client reach the Hermes control plane?

The "complete agent console" positioning depends on speaking the tui_gateway
JSON-RPC channel, not just the OpenAI-compatible data plane. Upstream issues
#32882 and #38412 report that channel being unreachable from packaged clients,
and rusty4444/hermes-android carries 312 lines of dead code that appear to be an
abandoned attempt at exactly this.

This probe answers, for Hermes v0.19.1 specifically:
  1. Does /api/ws accept a WebSocket upgrade from a non-Electron client?
  2. What authentication does it actually require?
  3. Does a JSON-RPC round trip complete?

Run with the Hermes venv python, which already has `websockets`:
    ~/.hermes/hermes-agent/venv/bin/python3 probe_b_plane.py [port]
"""

import asyncio
import json
import sys

import websockets
from websockets.exceptions import InvalidStatus

TOKEN = "caduceus-spike-token-do-not-reuse"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9219
BASE = f"127.0.0.1:{PORT}"


def show(label, ok, detail=""):
    mark = "PASS" if ok else "FAIL"
    print(f"  [{mark}] {label}" + (f" — {detail}" if detail else ""))


async def try_connect(path, token=None, headers=None, label=""):
    """Attempt one WebSocket upgrade, reporting exactly why it failed."""
    url = f"ws://{BASE}{path}"
    if token:
        url += f"?token={token}"
    try:
        async with websockets.connect(
            url,
            additional_headers=headers or {},
            open_timeout=8,
            close_timeout=2,
        ) as ws:
            show(label or path, True, "upgrade accepted")
            return "open"
    except InvalidStatus as e:
        code = e.response.status_code
        show(label or path, False, f"HTTP {code} on upgrade")
        return f"http_{code}"
    except asyncio.TimeoutError:
        show(label or path, False, "timeout")
        return "timeout"
    except Exception as e:  # noqa: BLE001 - probe reports whatever it hits
        show(label or path, False, f"{type(e).__name__}: {e}")
        return f"error_{type(e).__name__}"


async def jsonrpc_roundtrip(path, token=None):
    """Open the socket and attempt a real JSON-RPC exchange."""
    url = f"ws://{BASE}{path}"
    if token:
        url += f"?token={token}"
    try:
        async with websockets.connect(url, open_timeout=8) as ws:
            # Ask for something harmless and universally present before
            # touching session state.
            for method in ("initialize", "session.list", "status", "ping"):
                req = {"jsonrpc": "2.0", "method": method, "params": {}, "id": 1}
                await ws.send(json.dumps(req))
                try:
                    raw = await asyncio.wait_for(ws.recv(), timeout=5)
                except asyncio.TimeoutError:
                    print(f"    {method}: no response within 5s")
                    continue
                text = raw if isinstance(raw, str) else raw.decode()
                print(f"    {method}: {text[:220]}")
            return True
    except Exception as e:  # noqa: BLE001
        print(f"    round trip failed: {type(e).__name__}: {e}")
        return False


async def main():
    print(f"\nProbing Hermes control plane at {BASE}\n")

    print("1. WebSocket upgrade, no credentials")
    results = {}
    for path in ("/api/ws", "/api/events", "/api/pty", "/ws"):
        results[path] = await try_connect(path)

    print("\n2. WebSocket upgrade with an Origin header (Electron sends file://)")
    await try_connect("/api/ws", headers={"Origin": "file://"},
                      label="/api/ws  Origin: file://")
    await try_connect("/api/ws", headers={"Origin": f"http://{BASE}"},
                      label=f"/api/ws  Origin: http://{BASE}")

    print("\n3. WebSocket upgrade WITH the loopback session token")
    tok_result = await try_connect("/api/ws", token=TOKEN,
                                   label="/api/ws?token=<session token>")
    await try_connect("/api/ws", token="wrong-token",
                      label="/api/ws?token=<wrong>")

    print("\n4. JSON-RPC round trip on /api/ws (with token)")
    if tok_result == "open":
        await jsonrpc_roundtrip("/api/ws", token=TOKEN)
    else:
        print("    skipped — upgrade did not succeed")

    print()


if __name__ == "__main__":
    asyncio.run(main())
