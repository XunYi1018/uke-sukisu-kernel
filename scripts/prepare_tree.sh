#!/usr/bin/env bash
# Drop Kconfig "source" lines that point at files Xiaomi never open-sourced.
#
# The open-source uke tree references a few vendor-only directories (e.g.
# drivers/misc/hwid/Kconfig). Kconfig aborts the whole defconfig pass on the
# first unreadable source, so the tree cannot be configured as shipped.
# None of those modules are part of the boot kernel (the stock .config we
# build from has no CONFIG_MI_* entries), so commenting the lines out is safe.
#
# NOTE: Kconfig resolves a relative `source` path against $srctree (the kernel
# root), not against the directory of the including file. `lib/Kconfig` says
# `source "lib/math/Kconfig"` -- resolving that against lib/ would be wrong.

set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must be set}

group "Pruning Kconfig sources for un-shipped directories"
cd "$KERNEL_DIR"

omitted=0
while IFS= read -r kc; do
	[ -n "$kc" ] || continue
	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		ln=${entry%%:*}
		rest=${entry#*:}
		p=$(printf '%s' "$rest" | sed -nE 's/^[[:space:]]*source[[:space:]]+"?([^"[:space:]#]+)"?.*/\1/p')
		[ -n "$p" ] || continue
		# Skip absolute paths and variable expansion; only relative paths are ours.
		case "$p" in
			/*|\$*) continue ;;
		esac
		if [ ! -e "$p" ]; then
			sed -i "${ln}s|^|# OMITTED (not in open-source tree): |" "$kc"
			warn "omitted ${kc}:${ln} -> ${p}"
			omitted=$((omitted + 1))
		fi
	done < <(grep -nE '^[[:space:]]*source[[:space:]]' "$kc" 2>/dev/null || true)
done < <(find . -type f -name Kconfig -not -path './out/*' 2>/dev/null || true)

ok "pruned ${omitted} dangling Kconfig source line(s)"
endgroup
