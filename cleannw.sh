#!/bin/bash
# /TopStor/cleannw.sh
#
# Purpose:
#   Return the zfs container's network to its image-baked "creation state"
#   by reverting every change docker_setup.sh (and the helpers it calls —
#   reconcile_bonds.sh, create_bond.sh) makes on top of the baked image.
#
# What the patched v3 image has already baked (PRESERVE):
#   * Kernel interfaces: lo, eth0, eth10, docker0
#       eth10 is itself a kernel bond (qdisc MASTER flag) — the entrypoint
#       renames the image's bond0 → eth10 on every boot so NM can re-use
#       the name `bond0` for fresh bonds.
#   * NM connections — NAMES stable across image-builds, UUIDs unique per
#     image build:
#         cmynode      — bond    (ifname=eth10, carries 10.11.11.14)
#         clusterstub  — bond    (ifname=bond0 in the image; the kernel
#                                 bond0 the name references was renamed
#                                 to eth10 by the entrypoint, so DEVICE
#                                 is empty in nmcli)
#         ens3         — ethernet (image-baked phantom)
#         mycluster    — bond    (same as clusterstub)
#         mynode       — bond    (same as clusterstub)
#   * eth10 IPs: 10.11.11.14/32 (primary) + 10.11.11.250/24 (alias).
#
# What docker_setup.sh adds on top (REMOVE):
#   * NM connections whose NAME is one of the docker_setup-emitted bond
#     names: bond0, nm_bond, cm_bond, d_bond, ibond, cmycluster, cmy*
#     (any NM bond conn that does not have an image-baked name). NM
#     allows duplicate NAMEs across profiles (they are distinguished by
#     UUID), so even if a profile named `cmynode` has multiple instances
#     we keep one and target others via UUID-aware deletion.
#   * "slave-NIC-to-bond" ethernet connections (always docker_setup).
#   * Kernel bond devices ^bond[0-9]+$ that did NOT come pre-renamed by
#     the entrypoint (i.e. today's bondN devices are docker_setup-emitted
#     bonds, not the image's bond0).
#   * Alias IPs on stable ifaces (eth10:2 etc.) that docker_setup added
#     and never cleaned.
#
# Decision rule (NAME-based for connections):
#   BOND TYPE:
#     keep   iff NAME matches ^IMAGE_BAKED_BOND_RE$.
#     remove otherwise (bond0, nm_bond, cm_bond, d_bond, ibond, cmycluster, …).
#   ETHERNET TYPE:
#     keep   iff NAME matches ^IMAGE_BAKED_ETH_RE$ (currently just ens3).
#     remove otherwise — this catches all slave-* conns and any docker
#     setup-invented ethernet conn.
#   KERNEL:
#     remove any ^bond[0-9]+$ device. eth10 is preserved (different name).
#
# Idempotency: every step is best-effort. Re-runs are safe.

set +e

# Image-baked NM bond CONNECTION names — these MUST survive every cleannw run.
IMAGE_BAKED_BOND_RE='^(cmynode|mynode|mycluster|clusterstub)$'
# Image-baked ethernet CONNECTION names (phantom NICs).
IMAGE_BAKED_ETH_RE='^(ens3)$'
# Kernel bond NAMES docker_setup.sh is allowed to tear down.
BOND_KNAME_RE='^bond[0-9]+$'
# Master bond names emitted by reconcile_bonds.sh / create_bond.sh.
BOND_MASTER_NAMES='^(bond[0-9]+|nm_bond|cm_bond|d_bond|ibond|cmycluster)$'
# Slave conn NAME pattern (always docker_setup-created).
SLAVE_NAME_RE='^slave-[A-Za-z0-9_.-]+-to-[A-Za-z0-9_.-]+$'
# Ethernet type field as nmcli reports it (varies by NetworkManager version).
ETH_TYPE_RE='^(ethernet|802-3-ethernet)$'

echo "[cleannw] step 0/4 — disable autoconnect on kept image-baked bonds with ifname=bondN"
# Iterate by UUID (not NAME) because NM allows duplicate conn names; this
# way every instance is handled individually. We deliberately do NOT call
# `nmcli conn down` here because doing so on the image-baked cmynode
# would tear down the eth10 kernel device that the entrypoint depends on.
nmcli -t -f UUID,NAME,TYPE conn show 2>/dev/null \
    | awk -F: -v KEEP="$IMAGE_BAKED_BOND_RE" '
        $3 == "bond" && $2 ~ KEEP { print $1 ":" $2 }
    ' \
    | while IFS=: read -r uuid name; do
        ifname=$(nmcli -g connection.interface-name conn show uuid "$uuid" 2>/dev/null \
                 | awk 'NF{print; exit}')
        if [[ "$ifname" =~ $BOND_KNAME_RE ]]; then
            echo "    [~] $name uuid=${uuid:0:8} (ifname=$ifname) — autoconnect=no"
            nmcli conn modify uuid "$uuid" connection.autoconnect no 2>/dev/null
        fi
        # Image-baked `cmynode` references eth10 and ships with the IP
        # 10.11.11.14 baked into its profile. The user wants eth10 alive
        # but *without* an IP, so disable IPv4 on cmynode here as well —
        # do NOT use `nmcli conn down` (would tear down eth10).
        if [ "$name" = "cmynode" ]; then
            echo "    [~] cmynode uuid=${uuid:0:8} — ipv4.method=disabled (drop eth10 IP)"
            nmcli conn modify uuid "$uuid" ipv4.method disabled 2>/dev/null
            nmcli conn modify uuid "$uuid" ipv4.addresses "" 2>/dev/null
        fi
    done

# ----------------------------------------------------------------------
# Step 1: drop bond-slave connections.
# ----------------------------------------------------------------------
echo "[cleannw] step 1/4 — drop bond-slave connections"

echo "    [-] by NAME pattern (slave-NIC-to-*)"
nmcli -t -f NAME conn show 2>/dev/null \
    | grep -E "$SLAVE_NAME_RE" \
    | while read -r c; do
        echo "        $c"
        nmcli conn down "$c" 2>/dev/null
        nmcli conn delete "$c" 2>/dev/null
    done

echo "    [-] by SLAVE field (ethernet whose master is any docker_setup bond)"
while IFS=: read -r name type slave; do
    [ -n "$name" ] || continue
    [[ "$type" =~ $ETH_TYPE_RE ]] || continue
    [[ "$slave" =~ $BOND_MASTER_NAMES ]] || continue
    echo "        $name (master=$slave)"
    nmcli conn down "$name" 2>/dev/null
    nmcli conn delete "$name" 2>/dev/null
done < <(nmcli -t -f NAME,TYPE,SLAVE conn show 2>/dev/null)

# ----------------------------------------------------------------------
# Step 2: drop bond connections whose NAME is NOT image-baked.
#   Image-baked names: cmynode, mynode, mycluster, clusterstub. Anything
#   else is a docker_setup creation. NM allows multiple profiles to share
#   a name; we keep ALL of them when the name is in the keep set (the
#   image-baked one + any duplicates from docker_setup runs).
# ----------------------------------------------------------------------
echo "[cleannw] step 2/4 — drop non-image-baked bond connections"
nmcli -t -f NAME,TYPE conn show 2>/dev/null \
    | awk -F: -v KEEP="$IMAGE_BAKED_BOND_RE" '
        $2 == "bond" && $1 !~ KEEP { print $1 }
    ' | sort -u | while read -r c; do
    echo "    [-] $c"
    nmcli conn down "$c" 2>/dev/null
    nmcli conn delete "$c" 2>/dev/null
done

# ----------------------------------------------------------------------
# Step 3: drop ethernet connections whose NAME is NOT image-baked.
#   The image-baked `ens3` survives; everything else goes (includes any
#   slave-stamped conns with non-standard NAME that slipped past step 1).
# ----------------------------------------------------------------------
echo "[cleannw] step 3/4 — drop non-image-baked ethernet connections"
nmcli -t -f NAME,TYPE conn show 2>/dev/null \
    | awk -F: -v KEEP="$IMAGE_BAKED_ETH_RE" '
        $2 ~ /ethernet/ && $1 !~ KEEP { print $1 }
    ' | sort -u | while read -r c; do
    echo "    [-] $c"
    nmcli conn down "$c" 2>/dev/null
    nmcli conn delete "$c" 2>/dev/null
done

# ----------------------------------------------------------------------
# Step 4: drain residual kernel bond devices (^bond[0-9]+$).
#   Loop because NM can recreate a bond on demand from any connection
#   that has ifname=bondN and autoconnect=yes (even though we deleted
#   the bond0 NM connection, image-baked profiles like `mynode` still
#   reference ifname=bond0). The loop will repeatedly delete bond0;
#   it eventually settles when NM stops auto-recreating it. eth10 is
#   preserved (its name is `eth10`, not `bond\d+`).
# ----------------------------------------------------------------------
echo "[cleannw] step 4/4 — drain residual kernel bond devices (idempotent loop)"
CHANGED=1
ITER=0
while [ "$CHANGED" -eq 1 ] && [ "$ITER" -lt 10 ]; do
    CHANGED=0
    ITER=$((ITER+1))
    for iface in $(ls /sys/class/net/ 2>/dev/null | sort -u); do
        [[ "$iface" =~ $BOND_KNAME_RE ]] || continue
        SLAVES_FILE="/sys/class/net/$iface/bonding/slaves"
        if [ -r "$SLAVES_FILE" ]; then
            for slave in $(cat "$SLAVES_FILE" 2>/dev/null); do
                echo "    [-] detach slave $slave from $iface"
                echo "-$slave" > "$SLAVES_FILE" 2>/dev/null || true
                CHANGED=1
            done
        fi
        if ip link show "$iface" >/dev/null 2>&1; then
            echo "    [-] ip link delete $iface (iter $ITER)"
            ip link set "$iface" down 2>/dev/null
            ip link delete "$iface" 2>/dev/null
            CHANGED=1
        fi
    done
done
if [ "$ITER" -ge 10 ]; then
    echo "    [i] loop bounded at 10 iterations; some bond devices may persist (NM auto-recreating)."
fi

# Flush alias IPs on stable interfaces (docker_setup leftover eth10:2 etc.)
echo "[cleannw] step 4b/4 — flush alias IPs on stable ifaces"
for alias_dev in $(ip -o addr show 2>/dev/null \
                    | awk '{print $2}' \
                    | grep -E ':[0-9]+$' | sort -u || true); do
    echo "    [-] flush aliases on $alias_dev"
    ip addr flush dev "$alias_dev" 2>/dev/null || true
done

# ----------------------------------------------------------------------
# Step 4c/4: drop eth10 IP so it is an IP-less kernel bond.
#   eth10 stays alive as a kernel bond (and as a port of the inner
#   docker0 bridge, if /TopStor/ensure_eth10_bridge0.sh ran) but has
#   no IP of its own. Connection routes will go through eth0 instead.
# ----------------------------------------------------------------------
echo "[cleannw] step 4c/4 — drop IP from eth10 (leave kernel bond up, IP-less)"
if [ -d /sys/class/net/eth10 ]; then
    BEFORE=$(ip -o addr show dev eth10 2>/dev/null | awk '$2 == "inet" {print $4}')
    if [ -n "$BEFORE" ]; then
        echo "    [-] eth10 had: $BEFORE"
    fi
    ip -4 addr flush dev eth10 2>/dev/null || true
    ip -6 addr flush dev eth10 2>/dev/null || true
    AFTER=$(ip -o addr show dev eth10 2>/dev/null | awk '$2 ~ /^inet/ {print $4}')
    if [ -z "$AFTER" ]; then
        echo "    [ok] eth10 is now IP-less (kernel bond alive)"
    else
        echo "    [warn] eth10 still has: $AFTER (manual cleanup may be needed)"
    fi
else
    echo "    [=] eth10 not present — nothing to flush"
fi

# ----------------------------------------------------------------------
# Verification — print summary
# ----------------------------------------------------------------------
echo
echo "==== cleannw verification ===="
echo "Kernel interfaces:"
ls /sys/class/net/ | sort
echo
echo "NM connections:"
nmcli conn show
echo
echo "ip -br addr:"
ip -br addr show
echo
echo "[cleannw] done."
