#!/bin/bash
# /TopStor/docker-preload.sh
#
# Preload images required by docker_setup.sh into the DinD graph root
# (/docker-data, a host bind-mount), so:
#
#   * The moataznegm/quickstor:* image set is always available to
#     `docker run` inside the zfs container without re-pulling from the
#     internet on every restart.
#   * The actual image LAYERS live on the host filesystem (under
#     /root/topstor/volumes/zfs-docker-data/), NOT in the zfs image's
#     overlay. /TopStor/cleannw.sh-style cleanup of the container does
#     not blow away the image cache.
#
# Source of truth:
#   /docker-images/*.tar        — tarballs bind-mounted read-only from
#                                 /root/topstor/volumes/zfs-docker-images/
#
# Loaded into DinD's graph root, which itself is host-backed
# (/docker-data <-> /root/topstor/volumes/zfs-docker-data/).
#
# Idempotent: each load is gated by an existing-image check, so re-runs
# are no-ops. Failed loads are logged but do not abort — the rest of
# the cluster can still come up.

set +e

SRC_DIR="${DOCKER_PRELOAD_SRC:-/docker-images}"
GRAPH_ROOT="${DOCKER_DATA_ROOT:-/docker-data}"
LOG_PREFIX="[docker-preload]"

log() { echo "$LOG_PREFIX $*"; }

# Wait for dockerd to be ready (up to 30s)
log "waiting for dockerd at /var/run/docker.sock …"
for i in $(seq 1 30); do
    if [ -S /var/run/docker.sock ] && timeout 2 docker info >/dev/null 2>&1; then
        log "dockerd ready after ${i}s"
        break
    fi
    sleep 1
done
if ! timeout 2 docker info >/dev/null 2>&1; then
    log "ERROR: dockerd not up after 30s — skipping preload"
    exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
    log "no source dir at $SRC_DIR — skipping preload"
    exit 0
fi

# Count tarballs
TARBALLS=$(find "$SRC_DIR" -maxdepth 1 -type f -name '*.tar' | sort)
if [ -z "$TARBALLS" ]; then
    log "no .tar files in $SRC_DIR — skipping preload"
    exit 0
fi
N=$(echo "$TARBALLS" | wc -l)
log "loading up to $N tarball(s) from $SRC_DIR into $GRAPH_ROOT"

LOADED=0
SKIPPED=0
FAILED=0

for tar in $TARBALLS; do
    fname=$(basename "$tar")
    # Each tarball may contain multiple images/repos. Pull repo:tag out
    # of the filename for logging (moataznegm_quickstor_git.tar → moataznegm/quickstor:git).
    pretty=$(echo "$fname" | sed -E 's/\.tar$//; s/_/__/g; s|__|/|; s|_|:|')
    [ "${pretty%%:*}" = "${pretty}" ] && pretty="${pretty}:latest"

    # Try to short-circuit by checking if any image matching the expected
    # repo:tag is already present in DinD. This is best-effort: the loader
    # still runs for unmatched tarballs.
    already=0
    if timeout 10 docker image inspect "$pretty" >/dev/null 2>&1; then
        log "  [=] $pretty — already loaded; skipping $(basename "$tar")"
        SKIPPED=$((SKIPPED+1))
        continue
    fi

    log "  [+] loading $(basename "$tar") (expected repo:tag: $pretty)…"
    if timeout 120 docker load -i "$tar" >/tmp/docker-preload.out 2>&1; then
        LOADED=$((LOADED+1))
        # docker load prints "Loaded image: <repo>:<tag>" lines; surface them.
        grep -E 'Loaded image|already exists' /tmp/docker-preload.out | sed "s|^|$LOG_PREFIX   |"
    else
        FAILED=$((FAILED+1))
        log "  [!] load FAILED for $(basename "$tar"):"
        tail -3 /tmp/docker-preload.out | sed "s|^|$LOG_PREFIX       |"
    fi
done

log "summary: loaded=$LOADED  skipped=$SKIPPED  failed=$FAILED (total $N tarball(s))"

# Trim to keep image list visible for quick sanity-check
echo "$LOG_PREFIX images visible in DinD after preload:"
docker images --format "$LOG_PREFIX   {{.Repository}}:{{.Tag}}\t{{.Size}}" | sort
