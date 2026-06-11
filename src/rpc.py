"""
rpc.py - Lightweight JSON-RPC helpers for MEV detection.

No external web3 dependency; we use plain HTTP + eth_getBlockByNumber,
eth_getTransactionByHash, eth_getTransactionReceipt, and eth_call for
historical state. Works with any EVM-compatible RPC endpoint.
Base, Arbitrum, etc.).

Uses only the Python standard library (`urllib.request`) — no
`requests`, no `pip install` step needed.
"""
from __future__ import annotations
import json
import time
import urllib.request
import urllib.error
from typing import Any, Dict, List, Optional


class RpcError(Exception):
    pass


def _http_post_json(url: str, payload: Dict[str, Any], timeout: int = 30) -> Dict[str, Any]:
    """POST a JSON payload to `url` and return the parsed JSON response.

    Uses only `urllib.request` from the Python standard library.
    Raises RpcError on any HTTP error or JSON parse failure.
    """
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        raise RpcError(f"HTTP {e.code}: {e.reason}") from e
    except urllib.error.URLError as e:
        raise RpcError(f"URL error: {e.reason}") from e
    try:
        return json.loads(body)
    except json.JSONDecodeError as e:
        raise RpcError(f"non-JSON response: {body[:200]}") from e


class RpcClient:
    """Thin wrapper around a JSON-RPC endpoint with retry + basic rate-limit."""

    def __init__(self, url: str, timeout: int = 30, max_retries: int = 4):
        self.url = url
        self.timeout = timeout
        self.max_retries = max_retries
        self._id = 0

    def call(self, method: str, params: List[Any]) -> Any:
        self._id += 1
        payload = {
            "jsonrpc": "2.0",
            "id": self._id,
            "method": method,
            "params": params,
        }
        last_err: Optional[Exception] = None
        for attempt in range(self.max_retries):
            try:
                data = _http_post_json(self.url, payload, self.timeout)
                if "error" in data:
                    raise RpcError(data["error"].get("message", "rpc error"))
                return data.get("result")
            except RpcError as e:
                last_err = e
                time.sleep(0.4 * (2 ** attempt))
        raise RpcError(f"RPC {method} failed after {self.max_retries} attempts: {last_err}")

    # ---- high-level helpers ----

    def block_number(self) -> int:
        return int(self.call("eth_blockNumber", []), 16)

    def get_block(self, num: int, full_txs: bool = True) -> Dict[str, Any]:
        return self.call("eth_getBlockByNumber", [hex(num), full_txs])

    def get_tx_receipt(self, tx_hash: str) -> Dict[str, Any]:
        return self.call("eth_getTransactionReceipt", [tx_hash])

    def get_tx(self, tx_hash: str) -> Dict[str, Any]:
        return self.call("eth_getTransactionByHash", [tx_hash])

    def get_logs(self, params: Dict[str, Any]) -> List[Dict[str, Any]]:
        return self.call("eth_getLogs", [params])

    def chain_id(self) -> int:
        return int(self.call("eth_chainId", []), 16)
