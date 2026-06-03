"""
report.py - Format MEV exposure report for human or agent consumption.

Reads JSON output from detect_mev.py and renders it in three flavors:
  - text   (default, pretty terminal output)
  - markdown
  - html   (for embedding in a docs page / agent reply)
"""
from __future__ import annotations
import argparse
import json
import sys
from typing import Any, Dict


def render_text(r: Dict[str, Any]) -> str:
    lines = []
    lines.append("=" * 64)
    lines.append(f"  MEV EXPOSURE REPORT")
    lines.append(f"  Wallet: {r['wallet']}")
    lines.append(f"  ChainId: {r['chainId']}")
    lines.append("=" * 64)
    lines.append("")
    lines.append(f"  Scanned blocks:       {r['scannedBlocks']}")
    lines.append(f"  Victim swap txs:      {r['victimTxCount']}")
    lines.append(f"  Total MEV incidents:  {r['incidentCount']}")
    bc = r.get("byClass", {})
    lines.append(f"    - sandwich:         {bc.get('sandwich', 0)}")
    lines.append(f"    - frontrun:         {bc.get('frontrun', 0)}")
    lines.append(f"    - backrun:          {bc.get('backrun', 0)}")
    lines.append("")
    lines.append(f"  >>> MEV EXPOSURE SCORE: {r['exposureScore']} / 100 <<<")
    lines.append(f"  >>> TOTAL EST. LOSS:   ${r['totalEstimatedLossUsd']:.2f}     <<<")
    lines.append("")
    lines.append("  Top attacker addresses:")
    if r["topAttackers"]:
        for addr, n in r["topAttackers"]:
            lines.append(f"    {addr}  --  {n} incident(s)")
    else:
        lines.append("    (none)")
    lines.append("")
    if r["incidents"]:
        lines.append("  Incidents (up to 50 shown):")
        lines.append("  " + "-" * 60)
        for inc in r["incidents"][:50]:
            lines.append(
                f"  [{inc['attack_class']:>9}] block {inc['block']:<8} "
                f"victim {inc['victim_tx'][:14]}... "
                f"atk {inc['attacker'][:14]}... "
                f"conf {inc['confidence']:.2f}"
            )
    return "\n".join(lines) + "\n"


def render_markdown(r: Dict[str, Any]) -> str:
    lines = []
    lines.append(f"# MEV Exposure Report — `{r['wallet']}`")
    lines.append("")
    lines.append(f"- **ChainId:** {r['chainId']}")
    lines.append(f"- **Scanned blocks:** {r['scannedBlocks']}")
    lines.append(f"- **Victim swap txs:** {r['victimTxCount']}")
    bc = r.get("byClass", {})
    lines.append(f"- **Incidents:** {r['incidentCount']} "
                 f"(sandwich {bc.get('sandwich', 0)}, "
                 f"frontrun {bc.get('frontrun', 0)}, "
                 f"backrun {bc.get('backrun', 0)})")
    lines.append("")
    lines.append(f"## 🎯 MEV Exposure Score: **{r['exposureScore']} / 100**")
    lines.append(f"## 💸 Total Estimated Loss: **${r['totalEstimatedLossUsd']:.2f}**")
    lines.append("")
    if r["topAttackers"]:
        lines.append("## Top attacker addresses")
        lines.append("")
        lines.append("| Attacker | Incidents |")
        lines.append("|----------|-----------|")
        for addr, n in r["topAttackers"]:
            lines.append(f"| `{addr}` | {n} |")
        lines.append("")
    if r["incidents"]:
        lines.append("## Incidents")
        lines.append("")
        lines.append("| Class | Block | Victim tx | Attacker | Confidence |")
        lines.append("|-------|-------|-----------|----------|------------|")
        for inc in r["incidents"][:50]:
            lines.append(
                f"| {inc['attack_class']} | {inc['block']} | "
                f"`{inc['victim_tx'][:14]}…` | `{inc['attacker'][:14]}…` | "
                f"{inc['confidence']:.2f} |"
            )
    return "\n".join(lines) + "\n"


def render_html(r: Dict[str, Any]) -> str:
    bc = r.get("byClass", {})
    rows = ""
    for inc in r["incidents"][:50]:
        rows += (
            f"<tr><td>{inc['attack_class']}</td>"
            f"<td>{inc['block']}</td>"
            f"<td><code>{inc['victim_tx'][:14]}…</code></td>"
            f"<td><code>{inc['attacker'][:14]}…</code></td>"
            f"<td>{inc['confidence']:.2f}</td></tr>"
        )
    attackers = "".join(
        f"<li><code>{a}</code> — {n} incident(s)</li>"
        for a, n in r["topAttackers"]
    )
    return f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>MEV Exposure Report — {r['wallet']}</title>
<style>
  body {{ font: 14px/1.4 system-ui, sans-serif; max-width: 900px; margin: 32px auto; padding: 0 16px; color: #111; }}
  h1 {{ border-bottom: 2px solid #333; padding-bottom: 4px; }}
  .score {{ font-size: 28px; color: #c0392b; font-weight: 700; }}
  .loss  {{ font-size: 28px; color: #c0392b; font-weight: 700; }}
  table  {{ border-collapse: collapse; width: 100%; margin-top: 8px; }}
  th, td {{ border: 1px solid #ddd; padding: 6px 8px; text-align: left; font-size: 13px; }}
  th {{ background: #f4f4f4; }}
  code  {{ background: #f4f4f4; padding: 1px 4px; border-radius: 3px; }}
</style></head><body>
<h1>MEV Exposure Report</h1>
<p><strong>Wallet:</strong> <code>{r['wallet']}</code><br>
<strong>ChainId:</strong> {r['chainId']}<br>
<strong>Scanned blocks:</strong> {r['scannedBlocks']}</p>

<p class="score">MEV Exposure Score: {r['exposureScore']} / 100</p>
<p class="loss">Total Estimated Loss: ${r['totalEstimatedLossUsd']:.2f}</p>

<p><strong>Victim swap txs:</strong> {r['victimTxCount']} —
<strong>Incidents:</strong> {r['incidentCount']}
(sandwich {bc.get('sandwich',0)}, frontrun {bc.get('frontrun',0)}, backrun {bc.get('backrun',0)})</p>

<h2>Top attacker addresses</h2>
<ul>{attackers or "<li>(none)</li>"}</ul>

<h2>Incidents</h2>
<table>
<thead><tr><th>Class</th><th>Block</th><th>Victim tx</th><th>Attacker</th><th>Confidence</th></tr></thead>
<tbody>{rows or "<tr><td colspan='5'>No incidents detected</td></tr>"}</tbody>
</table>
</body></html>
"""


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--in", dest="input", default="-",
                   help="Input JSON file (default stdin)")
    p.add_argument("--format", choices=["text", "markdown", "html", "json"],
                   default="text")
    p.add_argument("--out", default="-", help="Output file (default stdout)")
    args = p.parse_args()

    raw = sys.stdin.read() if args.input == "-" else open(args.input).read()
    r = json.loads(raw)

    if args.format == "json":
        out = json.dumps(r, indent=2)
    elif args.format == "markdown":
        out = render_markdown(r)
    elif args.format == "html":
        out = render_html(r)
    else:
        out = render_text(r)

    if args.out == "-":
        sys.stdout.write(out)
    else:
        with open(args.out, "w") as f:
            f.write(out)


if __name__ == "__main__":
    main()
