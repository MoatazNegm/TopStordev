#!/bin/bash
set -e
echo "[abdopuppet] starting services…"
mkdir -p /srv/git
chmod 755 /srv/git
mkdir -p /var/cache/lighttpd/uploads /var/cache/lighttpd/compress /var/log/lighttpd /run/lighttpd
chown -R lighttpd:lighttpd /var/cache/lighttpd /var/log/lighttpd /run/lighttpd 2>/dev/null || true
/usr/sbin/sshd
echo "[abdopuppet] sshd started"
# Mark every bare repo as git-daemon-exportable (abdopuppet convention)
find /srv/git -maxdepth 2 -type d -name "*.git" -exec touch {}/git-daemon-export-ok \; 2>/dev/null || true
# Bypass git's safe.directory check: the bare repos here are owned by the
# host DinD user (uid 33 / tape), not by the user inside this container.
# Without this, every git operation on /srv/git/*.git fails with
# "fatal: detected dubious ownership in repository".
git config --global --add safe.directory '*'
# Start git-daemon (receive-pack + export-all + reuseaddr)
git daemon \
    --reuseaddr \
    --export-all \
    --enable=receive-pack \
    --base-path=/srv/git \
    --listen=0.0.0.0 \
    --port=9418 \
    --detach \
    --pid-file=/var/run/git-daemon.pid \
    /srv/git
echo "[abdopuppet] git-daemon started on :9418"
exec /usr/sbin/lighttpd -D -f /etc/lighttpd/lighttpd.conf
