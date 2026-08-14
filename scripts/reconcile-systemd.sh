#!/usr/bin/env bash
set -euo pipefail

SRC="/opt/oikos/docker/systemd"
DEST="/etc/systemd/system"

desired=""
for f in "$SRC"/*.service "$SRC"/*.timer; do
  [ -e "$f" ] || continue
  desired="${desired} $(basename "$f")"
done

for installed in "$DEST"/oikos-*.service "$DEST"/oikos-*.timer; do
  [ -e "$installed" ] || continue
  name=$(basename "$installed")
  case " ${desired} " in
    *" ${name} "*) continue ;;
  esac
  sudo systemctl disable --now "$name" 2>/dev/null || true
  sudo rm -f "$installed"
  echo "Unit removida (nao existe mais no repo): ${name}"
done

for name in ${desired}; do
  sudo cp "${SRC}/${name}" "${DEST}/${name}"
done

sudo systemctl daemon-reload

for name in ${desired}; do
  case "$name" in
    *.timer) sudo systemctl enable --now "$name" ;;
  esac
done
