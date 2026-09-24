#!/bin/bash
# /TopStor/reboot.sh  (bind-mounted into the zfs container at /workspace/TopStor/reboot.sh)
#
# Purpose:
#   Simulate the hardest possible "physical reboot" of THIS container —
#   like yanking the power cord and plugging it back in. The container
#   exits and Docker's `restart: unless-stopped` policy brings it back
#   up, re-running the entrypoint, docker-preload.sh, and (unless
#   /tmp/docker_setup_disabled is mounted) docker_setup.sh.
#
# Why this exists (do NOT just call `reboot` from inside):
#   The plain `reboot`/`shutdown -r now`/`systemctl reboot`/`init 6`
#   commands inside this privileged container call the host kernel's
#   reboot(2) syscall (CAP_SYS_BOOT + shared kernel via --privileged).
#   That reboots the ENTIRE HOST, not just this container. Almost never
#   what the caller wants.
#
# Why we do NOT blindly `kill -KILL 1` either:
#   * In containerized PID namespaces, the kernel silently no-ops
#     SIGKILL against PID 1 (init protection) even from privileged
#     senders — the syscall returns 0 but the signal is not delivered.
#   * In some image setups (DinD, host-PID-shared images), signaling
#     PID 1 of the host's namespace can leak from inside the container
#     and shut the host down. We MUST verify PID namespace isolation
#     before signaling PID 1.
#
# How this script does the hard reset (in strict order of preference):
#   1. `docker -H unix:///var/run/docker.sock restart <name>`
#      Use this ONLY when the socket we reach is the host's docker
#      daemon — i.e. `docker ps` from here shows our own container.
#      Most useful when called from a "sidecar" container with the host
#      socket bind-mounted, OR when called from the host itself.
#   2. Send SIGTERM to PID 1 of THIS container's PID namespace.
#      Used when we're inside a container whose `/var/run/docker.sock`
#      is its OWN DinD daemon (cannot see the outer container). systemd
#      (or any well-behaved init) responds by running its shutdown
#      hooks, services stop, PID 1 exits, the container exits, and
#      Docker's restart policy brings it back. This stays inside our
#      PID namespace — host untouched.
#   3. If SIGTERM is ignored after 5 s, escalate to SIGRTMIN+3 —
#      systemd's explicit shutdown signal. Same namespace safety.
#   4. As a final in-namespace fallback, SIGKILL PID 1.
#
# How this script decides whether signaling PID 1 is safe:
#   Three checks, in order of decreasing confidence. ANY passing → safe.
#
#   A. /proc/self/cgroup has a container marker
#      (docker-, docker/, docker.scope, containerd-, kubepods, …).
#      Strongest: we are ourselves in a container cgroup.
#
#   B. /proc/1/cgroup has a container marker AND /proc/1/cmdline does
#      NOT contain --switched-root.
#      Strong: PID 1 is a containerized init (not the host's systemd).
#
#   C. Inner DinD dockerd is reachable and `/var/run/docker.sock` is
#      the DinD socket (NOT the host socket). DinD REQUIRES an isolated
#      PID namespace to run, so if we can talk to our own dockerd,
#      we are in our own namespace. False positives on this check
#      alone are possible (e.g., running from the host with a hostname
#      that doesn't match any container), so this is the WEAKEST signal
#      and used as a fallback, not the primary check.
#
# Override:
#   REBOOT_FORCE_PID1=1   skip ALL detection and signal PID 1 directly.
#                         The operator is asserting "I know what I'm
#                         doing; this is a container with PID namespace
#                         isolation." Use only if you understand the
#                         risk: with `pid: host`, this would tear down
#                         the host.
#
# How this script REFUSES to act (safety):
#   * If we cannot verify PID namespace isolation AND REBOOT_FORCE_PID1
#     is not set, the script REFUSES to signal PID 1 and exits non-zero.
#   * `kill -KILL 1` is NEVER the first action. It is also NEVER sent
#     to anything that could be the host's init.
#   * `/sbin/reboot`, `systemctl reboot`, `init 6`, `shutdown -r` are
#     NEVER invoked.
#
# Idempotency: this script always terminates the caller's process.
#
# Env vars (optional):
#   REBOOT_MARKER        override marker file path (default /root/last_hard_reboot)
#   REBOOT_REASON        free-form reason in marker (default "hard_reset_via_reboot.sh")
#   REBOOT_CONTAINER     override container name (default: hostname -s)
#   REBOOT_FORCE_PID1    set to 1 to bypass isolation detection

set +e

LOG_PREFIX="[reboot.sh]"
log() { echo "$LOG_PREFIX $*" >&2; }

MARKER="${REBOOT_MARKER:-/root/last_hard_reboot}"
REASON="${REBOOT_REASON:-hard_reset_via_reboot.sh}"
MYCONTAINER="${REBOOT_CONTAINER:-$(hostname -s 2>/dev/null || echo zfs)}"
FORCE_PID1="${REBOOT_FORCE_PID1:-0}"

CMDLINE=$(cat /proc/$$/cmdline 2>/dev/null | tr '\0' ' ' || echo unknown)
HOSTN=$(hostname 2>/dev/null || echo unknown)

log "hard reset requested"
log "  pid=$$ ppid=$PPID"
log "  hostname=$HOSTN"
log "  container=$MYCONTAINER"
log "  cmdline=$CMDLINE"
log "  reason=$REASON"
log "  marker=$MARKER"
[ "$FORCE_PID1" = "1" ] && log "  REBOOT_FORCE_PID1=1 — isolation detection will be skipped"

# 0) marker
mkdir -p "$(dirname "$MARKER")" 2>/dev/null
{
    echo "iso=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
    echo "epoch=$(date -u +%s 2>/dev/null || echo unknown)"
    echo "reason=$REASON"
    echo "trigger_pid=$$"
    echo "trigger_ppid=$PPID"
    echo "trigger_cmdline=$CMDLINE"
    echo "hostname=$HOSTN"
    echo "container=$MYCONTAINER"
    echo "force_pid1=$FORCE_PID1"
} > "$MARKER" 2>/dev/null
sync 2>/dev/null

CGROUP_CONTAINER_RE='(docker-|docker/|docker\.scope|containerd-|kubepods|cri-containerd)'

# ----------------------------------------------------------------------------
# detect_dind_socket — return 0 if /var/run/docker.sock is an INNER DinD
# socket, 1 if it is the host daemon, 2 if no socket at all.
#
# Trick: a host socket will see ALL containers (typically many). A DinD
# socket sees only DinD-managed containers. So we look at the TOTAL count
# of containers, not just whether `name=^ours$` matches:
#   * host daemon: usually shows many containers
#   * DinD daemon: usually shows few (0–N) containers, mostly the DinD
#     children (etcd, etcdclient, intsmb, intdns, software, …)
# Additionally, we cross-check with the cgroup of PID 1 to be safe.
# ----------------------------------------------------------------------------
detect_dind_socket() {
    if [ ! -S /var/run/docker.sock ] || ! command -v docker >/dev/null 2>&1; then
        return 2
    fi
    # Does the daemon reachable from here see our own container?
    seen=$(docker -H unix:///var/run/docker.sock ps \
                --filter "name=^${MYCONTAINER}\$" \
                --format '{{.Names}}' 2>/dev/null | head -1)
    if [ "$seen" = "$MYCONTAINER" ]; then
        return 1  # host daemon (sees us)
    fi
    # The socket sees SOMETHING. If it sees the host's set of containers
    # (multiple, with images like nginx, etc.), it's the host daemon —
    # not DinD, even if our name doesn't match. If it sees 0 containers
    # or only DinD-related containers, it's DinD.
    total=$(docker -H unix:///var/run/docker.sock ps --format '{{.Names}}' 2>/dev/null | wc -l)
    if [ "$total" -ge 3 ]; then
        # Many containers visible — almost certainly the host daemon.
        # Returning 1 even though our name didn't match (could be that
        # we're called from a sidecar without the host container's name).
        return 1
    fi
    return 0
}

# ----------------------------------------------------------------------------
# detect_should_signal_p1 — return 0 if signaling PID 1 is safe (we are
# in a container with isolated PID namespace), 1 otherwise.
#
# Three checks (any one passing → safe):
#   A. /proc/self/cgroup has a container marker (we are in a container).
#   B. /proc/1/cgroup has a container marker AND PID 1's cmdline does
#      NOT look like host systemd (--switched-root).
#   C. Inner DinD dockerd is reachable AND PID 1's cmdline does NOT
#      look like host systemd.
# ----------------------------------------------------------------------------
detect_should_signal_p1() {
    if [ "$FORCE_PID1" = "1" ]; then
        log "  REBOOT_FORCE_PID1 set — bypassing detection"
        return 0
    fi

    p1_cmdline=""
    if [ -r /proc/1/cmdline ]; then
        p1_cmdline=$(tr '\0' ' ' < /proc/1/cmdline 2>/dev/null)
    fi
    p1_looks_like_host_init=0
    if echo "$p1_cmdline" | grep -q -- '--switched-root'; then
        p1_looks_like_host_init=1
    fi

    # Check A: are WE in a container cgroup?
    self_in_container=0
    if [ -r /proc/self/cgroup ] \
        && grep -qE "$CGROUP_CONTAINER_RE" /proc/self/cgroup 2>/dev/null; then
        self_in_container=1
    fi

    # Check B: is PID 1 in a container cgroup (and not host init)?
    p1_in_container=0
    if [ -r /proc/1/cgroup ] \
        && grep -qE "$CGROUP_CONTAINER_RE" /proc/1/cgroup 2>/dev/null; then
        p1_in_container=1
    fi

    if [ "$self_in_container" = "1" ]; then
        log "  isolation evidence: /proc/self/cgroup has a container marker"
        if [ "$p1_looks_like_host_init" = "0" ]; then
            return 0
        fi
        log "  BUT /proc/1/cmdline looks like host init — refusing for safety"
        log "      (this combination suggests pid: host; bypassing"
        log "       detection would risk killing the host)"
        return 1
    fi

    if [ "$p1_in_container" = "1" ] && [ "$p1_looks_like_host_init" = "0" ]; then
        log "  isolation evidence: /proc/1/cgroup has a container marker,"
        log "      and /proc/1/cmdline does not look like host init"
        return 0
    fi

    # Check C: DinD reachable + PID 1 not host init.
    detect_dind_socket
    if [ $? -eq 0 ] && [ "$p1_looks_like_host_init" = "0" ]; then
        log "  isolation evidence: inner DinD dockerd is reachable"
        log "      (DinD requires an isolated PID namespace)"
        log "      and /proc/1/cmdline does not look like host init"
        return 0
    fi

    log "  isolation evidence: NONE"
    log "      /proc/self/cgroup container_marker=${self_in_container}"
    log "      /proc/1/cgroup container_marker=${p1_in_container}"
    log "      /proc/1/cmdline host_init=${p1_looks_like_host_init}"
    return 1
}

# ----------------------------------------------------------------------------
# 1) PRIMARY: docker restart over a HOST docker socket.
# ----------------------------------------------------------------------------
detect_dind_socket
dind_rc=$?
if [ "$dind_rc" = "1" ]; then
    log "primary path: docker restart on HOST daemon — $MYCONTAINER visible"
    log "  (this restarts the outer container; host init untouched)"
    docker -H unix:///var/run/docker.sock restart -t 30 "$MYCONTAINER" 2>&1 \
        | sed "s|^|$LOG_PREFIX |" >&2
    sleep 5
    log "docker restart returned; container should be coming back up"
    exit 0
fi

if [ "$dind_rc" = "0" ]; then
    log "docker socket reachable but inner DinD — cannot restart outer container from here"
    log "  falling through to in-namespace PID 1 signaling"
else
    log "no docker socket at /var/run/docker.sock — falling through to in-namespace PID 1 signaling"
fi

# ----------------------------------------------------------------------------
# 2) FALLBACK: in-namespace PID 1 signaling.
# ----------------------------------------------------------------------------
if ! detect_should_signal_p1; then
    log "REFUSING to signal PID 1: cannot verify PID namespace isolation."
    log "  See isolation evidence lines above for which checks failed."
    log "  Override (operator-only, accepts risk):"
    log "      REBOOT_FORCE_PID1=1 /TopStor/reboot.sh"
    log "  Manual recovery from the host:"
    log "      docker restart $MYCONTAINER"
    exit 64
fi
log "PID namespace isolation verified — safe to signal container's PID 1"

# 2a) SIGTERM
log "sending SIGTERM to PID 1 (graceful shutdown)"
kill -TERM 1 2>/dev/null
for i in $(seq 1 5); do
    if ! kill -0 1 2>/dev/null; then
        log "PID 1 exited after ${i}s on SIGTERM — container is exiting"
        exit 0
    fi
    sleep 1
done
log "PID 1 still alive 5s after SIGTERM — escalating"

# 2b) SIGRTMIN+3 (systemd shutdown)
log "sending SIGRTMIN+3 to PID 1 (systemd's shutdown signal)"
kill -SIGRTMIN+3 1 2>/dev/null
for i in $(seq 1 30); do
    if ! kill -0 1 2>/dev/null; then
        log "PID 1 exited after ${i}s on SIGRTMIN+3 — container is exiting"
        exit 0
    fi
    sleep 1
done
log "PID 1 still alive 30s after SIGRTMIN+3"

# 2c) SIGKILL PID 1 (last in-namespace resort)
log "escalating to SIGKILL on PID 1 (in-namespace)"
kill -KILL 1 2>/dev/null
sleep 2
if ! kill -0 1 2>/dev/null; then
    log "PID 1 killed — container is exiting"
    exit 0
fi

log "ALL PATHS EXHAUSTED — could not make PID 1 exit"
log "  /var/run/docker.sock: DinD or absent (cannot reach host daemon)"
log "  SIGTERM, SIGRTMIN+3, SIGKILL on PID 1: all no-op'd or rejected"
log "  Manual recovery: from the host run"
log "      docker restart $MYCONTAINER"
exit 70
