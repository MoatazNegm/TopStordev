#!/bin/bash
set -euo pipefail

# Hardened React rebuild & container startup script

TEMPLHTTP='/TopStor/httpd_template.conf'
SHTTPDF='/TopStordata/httpd.conf'
TOPSTORWEB='/topstorweb'
BUILD_DIR="$TOPSTORWEB/build_react"
HTTPD_IMAGE='moataznegm/quickstor:git'
FLASK_IMAGE='moataznegm/quickstor:flask3'
BUILD_IMAGE='quickstor-ui:latest'

err() {
    echo "[ERROR] $*" >&2
    exit 1
}

info() {
    echo "[INFO] $*"
}

# Stop existing UI/API containers (ignore errors if they do not exist)
info "Stopping existing containers ..."
docker rm -f httpd flask react-dev-ui 2>/dev/null || true

# Get leader/cluster IP from etcd
info "Determining cluster IP from etcd ..."
myclusterip=$(docker exec etcdclient /TopStor/etcdgetlocal.py leaderip 2>/dev/null | tr -d '[:space:]') || true
if [ -z "$myclusterip" ]; then
    err "Could not determine cluster IP from etcd"
fi

# Prepare httpd config
info "Preparing httpd configuration ..."
rm -rf "$SHTTPDF"
cp "$TEMPLHTTP" "$SHTTPDF"
sed -i "s/MYCLUSTERH/$myclusterip/g" "$SHTTPDF"
sed -i "s/MYCLUSTER/$myclusterip/g" "$SHTTPDF"

# Verify required source files/directories exist before building
info "Verifying React source files ..."
required_files=(
    "$TOPSTORWEB/index.html"
    "$TOPSTORWEB/vite.config.js"
    "$TOPSTORWEB/postcss.config.js"
    "$TOPSTORWEB/tailwind.config.js"
)
for f in "${required_files[@]}"; do
    [ -e "$f" ] || err "Required file missing: $f"
done
[ -d "$TOPSTORWEB/src" ] || err "Required directory missing: $TOPSTORWEB/src"
[ -d "$TOPSTORWEB/public" ] || err "Required directory missing: $TOPSTORWEB/public"

# Build React UI using host source
info "Building React UI into $BUILD_DIR ..."
mkdir -p "$BUILD_DIR"
docker run --rm \
  -v "$BUILD_DIR:/app/build_react" \
  -v "$TOPSTORWEB/src:/app/src" \
  -v "$TOPSTORWEB/public:/app/public" \
  -v "$TOPSTORWEB/index.html:/app/index.html" \
  -v "$TOPSTORWEB/vite.config.js:/app/vite.config.js" \
  -v "$TOPSTORWEB/postcss.config.js:/app/postcss.config.js" \
  -v "$TOPSTORWEB/tailwind.config.js:/app/tailwind.config.js" \
  "$BUILD_IMAGE" npm run build

# Verify build output was produced
if [ ! -f "$BUILD_DIR/index.html" ]; then
    err "React build failed: $BUILD_DIR/index.html not found"
fi

# Start httpd container
info "Starting httpd container ..."
docker run -d --rm --name httpd --hostname shttpd --net bridge0 \
  -v /etc/localtime:/etc/localtime:ro \
  -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
  -p "$myclusterip":19999:19999 \
  -p "$myclusterip":81:81 \
  -p "$myclusterip":443:443 \
  -v "$SHTTPDF:/usr/local/apache2/conf/httpd.conf" \
  -v /root/topstorwebetc:/usr/local/apache2/topstorwebetc \
  -v "$TOPSTORWEB:/usr/local/apache2/htdocs/" \
  "$HTTPD_IMAGE"

# Verify httpd is running
sleep 2
if ! docker ps --filter 'name=^httpd$' --format '{{.Names}}' | grep -qx httpd; then
    err "httpd container failed to start"
fi

# Start flask container
info "Starting flask container ..."
docker run -d --rm --name flask --hostname apisrv \
  -v /etc/localtime:/etc/localtime:ro \
  -v /pace/:/pace \
  -v /pacedata/:/pacedata/ \
  -v /root/gitrepo/resolv.conf:/etc/resolv.conf \
  --net bridge0 \
  -p "$myclusterip":5001:5001 \
  -v /TopStor/:/TopStor \
  -v /TopStordata/:/TopStordata \
  "$FLASK_IMAGE"

# Verify flask is running
sleep 2
if ! docker ps --filter 'name=^flask$' --format '{{.Names}}' | grep -qx flask; then
    err "flask container failed to start"
fi

info "React UI rebuild and container startup completed."
