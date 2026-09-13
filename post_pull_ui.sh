#!/bin/sh
# post_pull_ui.sh - rebuild the UI docker image, save it, apply it, reboot.
# Designed to be called from systempull.sh after the git pulls complete.
# Keep it in /TopStor so it sits next to pre_apply.sh.

set -e

TOPSTORWEB=/topstorweb
TOPSTOR=/TopStor
TAR="$TOPSTOR/quickstor-ui.tar.gz"

echo "[post_pull_ui] running /TopStor/build-ui.sh (it cds to /topstorweb itself) ..."
if ! /TopStor/build-ui.sh; then
	echo "[post_pull_ui] build failed - aborting (no save, no reboot)" >&2
	exit 1
fi

echo "[post_pull_ui] saving image -> $TAR"
if ! docker save quickstor-ui:latest | gzip > "$TAR"; then
	echo "[post_pull_ui] docker save failed - aborting (no reboot)" >&2
	exit 1
fi

if docker ps >/dev/null 2>&1; then
	echo "[post_pull_ui] running pre_apply.sh ..."
	/TopStor/pre_apply.sh || echo "[post_pull_ui] pre_apply.sh returned non-zero, continuing to reboot"
else
	echo "[post_pull_ui] docker not running - skipping pre_apply.sh"
fi

echo "[post_pull_ui] done - rebooting in 5s"
sleep 5
reboot

