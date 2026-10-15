#!/usr/bin/env bash
# Static test gate for the claude-orchestrator plugin.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
err() { echo "FAIL: $*"; fail=1; }

# --- manifests -------------------------------------------------------------
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
	[ -f "$f" ] || err "missing $f"
done
if [ -f .claude-plugin/plugin.json ]; then
	out=$(claude plugin validate .claude-plugin/plugin.json 2>&1) || err "plugin.json invalid"
	echo "$out" | grep -qi 'warning' && { echo "$out"; err "plugin.json has warnings"; }
fi
if [ -f .claude-plugin/marketplace.json ]; then
	out=$(claude plugin validate . 2>&1) || err "marketplace invalid"
	echo "$out" | grep -qi 'warning' && { echo "$out"; err "marketplace has warnings"; }
	[ "$(jq -r '.name' .claude-plugin/marketplace.json)" = td-orchestrator ] || err "marketplace name"
	[ "$(jq -r '.plugins[0].name' .claude-plugin/marketplace.json)" = td-orchestrator ] || err "marketplace plugin name"
fi

# --- checks (extended by later tasks) --------------------------------------

[ "$fail" = 0 ] && echo "check.sh: all green"
exit "$fail"
