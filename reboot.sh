#!/bin/bash
# /TopStor/reboot.sh
#
# Purpose:
#   Simulate the hardest possible "physical reboot" from inside a Docker
#   container — like yanking the power cord from a server and plugging it
#   back in. Nothing runs shutdown hooks; nothing flushes cleanly; the
#   kernel reclaims the PID namespace instantly.
#
# Why this exists (do NOT just call `reboot` from inside):
#   The `zfs` service in docker-compose.yml runs with
#       privileged: true
#       restart: unless-stopped
#   and shares the host kernel. With --privileged the container has
#   CAP_SYS_BOOT, so the in-container `reboot`/`shutdown -r now`/
#   `systemctl reboot`/`init 6` paths all succeed — but they call the
#   *host* kernel's reboot(2) syscall, rebooting the entire host machine,
#   not just this container. After the host comes back, Docker restarts
#   this container because of `restart: unless-stopped`. Net effect: a
#   full host reboot disguised as a container reboot. That is almost
#   never what a script calling `reboot` actually wants.
#
#   This helper instead ends PID 1 (the entrypoint, which is
#   `tail -f /dev/null`). The host-side dockerd sees the container exit
#   and applies the restart policy, which is exactly the container-side
#   analog of a physical reboot: re-run entrypoint → re-run docker-
#   preload.sh → (re-)run docker_setup.sh.
#
# How it does the hard reset:
#   1. Write a marker file (/root/last_hard_reboot by default) so post-
#      restart logs/diagnostics can distinguish a hard reset from a clean
#      shutdown. /root is bind-mounted from the host (./volumes/linux-env),
#      so the marker persists across restarts.
#   2. Best-effort `sync` so the marker reaches disk.
#   3. `kill -KILL 1` — SIGKILL is uncatchable. There is no shutdown hook
#      to run, no graceful disconnect, no fsck-equivalent. Just like a
#      real power loss: the kernel reclaims everything within nanoseconds.
#      Docker sees the container exit with code 137 and restarts it.
#   4. Escalation: if PID 1 somehow refuses SIGKILL (a future entrypoint
#      swap could pin it), we wait REBOOT_GRACE seconds and then kill
#      our own process group and PID 1 again.
#
# Idempotency: the script always terminates the caller's process via the
# exit at the bottom. It is safe to call from anywhere — the caller
# should not expect to run anything after the call returns.
#
# Env vars (optional):
#   REBOOT_MARKER    override marker file path   (default /root/last_hard_reboot)
#   REBOOT_REASON    free-form reason in marker  (default "hard_reset_via_reboot.sh")
#   REBOOT_GRACE     seconds to wait before escalation  (default 1)

set +e

LOG_PREFIX="[reboot.sh]"

log() {
    # stderr so it shows up in `docker logs` regardless of stdout buffering
    echo "$LOG_PREFIX $*" >&2
}

MARKER="${REBOOT_MARKER:-/root/last_hard_reboot}"
REASON="${REBOOT_REASON:-hard_reset_via_reboot.sh}"
GRACE="${REBOOT_GRACE:-1}"

CMDLINE=$(cat /proc/$$/cmdline 2>/dev/null | tr '\0' ' ' || echo unknown)
HOSTN=$(hostname 2>/dev/null || echo unknown)

log "hard reset requested"
log "  pid=$$ ppid=$PPID"
log "  hostname=$HOSTN"
log "  cmdline=$CMDLINE"
log "  reason=$REASON"
log "  marker=$MARKER grace=${GRACE}s"

# 1) marker (write BEFORE the kill so it survives)
{
    echo "iso=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "epoch=$(date -u +%s 2>/dev/null || echo unknown)"
    echo "reason=$REASON"
    echo "trigger_pid=$$"
    echo "trigger_ppid=$PPID"
    echo "trigger_cmdline=$CMDLINE"
    echo "hostname=$HOSTN"
} > "$MARKER" 2>/dev/null

# 2) best-effort flush
sync 2>/dev/null

# 3) the actual hard reset: SIGKILL PID 1 (uncatchable)
log "sending SIGKILL to PID 1 (entrypoint) — power-loss simulation"
kill -KILL 1 2>/dev/null

# 4) escalation: only reachable if a future entrypoint refuses SIGKILL
sleep "$GRACE" 2>/dev/null
if kill -0 1 2>/dev/null; then
    log "PID 1 still alive after SIGKILL — escalating to process-group SIGKILL"
    kill -KILL -$$ 2>/dev/null
    kill -KILL 0  2>/dev/null
    sleep 1
fi

# If we are still alive at this point, just exit so the caller's caller
# (typically a script) doesn't hang.
log "fallback exit"
exit 137