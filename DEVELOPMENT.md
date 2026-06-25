# TopStor Development Guide

> Auto-generated from codebase investigation on 2026-06-16.
> This document summarizes the architecture of the TopStor storage appliance across its three main codebases: `/TopStor`, `/pace`, and `/topstorweb`.

---

## 1. System Overview

TopStor is a clustered software-defined storage appliance built on:
- **OS**: CentOS Stream 9
- **Storage**: ZFS on Linux (pools, raids, volumes, snapshots)
- **Clustering**: etcd for distributed configuration & leader election
- **Messaging**: RabbitMQ (systemd service) for inter-node command dispatch
- **Front-end**: React 18 + Vite + Tailwind CSS
- **API**: Flask (Python 3) exposed on port 5001
- **Containerization**: Docker for etcd, Flask API, Apache (UI), DNS, Samba, monitoring

### High-Level Flow
```
React UI (Apache/httpd Docker)
   | HTTP/HTTPS (port 80/443)
   v
Flask API (fapi.py in flask Docker, port 5001)
   | etcd read/write + RabbitMQ sendhost()
   v
Action Scripts (/TopStor/*.py, *.sh)
   | ZFS / targetcli / nmcli / system commands
   v
Hardware / Storage
```

---

## 2. Directory Structure

### 2.1 `/TopStor` — Core Logic & API

| File / Pattern | Purpose |
|----------------|---------|
| `fapi.py` | **Flask REST API** (port 5001). Endpoints for pools, volumes, snapshots, users, groups, hosts, replication, software updates, telemetry. Uses token-based auth with `login_required` decorator. |
| `docker_setup.sh` | **Node initialization** script. Configures bonds, firewall, Docker containers, etcd cluster membership, initial syncs. Run on every boot / node join. |
| `docker_primary.sh` | **Leader promotion** script. Reconfigures etcd as primary, starts Grafana, httpd forwarder, flask. |
| `iscsiwatchdog.sh` | Monitors iSCSI target changes (`targetcli`, `lsscsi`), refreshes disks, manages temporary init IP (`10.11.11.254`) for leader setup. |
| `ServiceWatchdog.sh` | Legacy systemd watchdog for `httpd`, `topstorremote`, `topstorremoteack`, `chronyc`. |
| `httpdflask.sh` | Spins up a local Apache forwarder (port 8080) used briefly during leader initialization. |
| `action*.py`, `VolumeCreate*.py`, `SnapshotCreate*.py`, `Unix*.py`, `Partner*.py` | **Action scripts** executed by the API or sync engine to mutate system state. |
| `etcdget.py`, `etcdput.py`, `etcddel.py`, `etcdgetlocalpy.py` | Thin wrappers around `etcdctl` for cluster-wide and local etcd access. |
| `sendhost.py` | RabbitMQ-based message dispatcher used by `postchange()` to forward commands to target nodes. |
| `logmsg.py` | Centralized logging with message codes from `msgsglobal.txt`. |
| `promserver.sh`, `promrepli.sh` | Prometheus / Grafana service orchestration. |
| `topstorwebetc/` | TLS certs (`TopStor.crt`, `.key`), Apache configs (`httpd.conf`, `httpd2.conf`). |
| `prometheus.files/`, `grafana/` | Monitoring config templates. |
| `key/` | GPG keys, certificates, replication certs. |

### 2.2 `/pace` — Background Services & Synchronization

| File / Pattern | Purpose |
|----------------|---------|
| `checksyncs.py` | **Sync orchestrator**. Reads/writes etcd `sync/` keys to propagate config changes across the cluster (users, groups, pools, volumes, cron, network, etc.). Modes: `syncinit`, `syncrequest`, `syncall`, `restetcd`, `replisyncrequest`. |
| `heartbeat.py` | **Cluster heartbeat**. Polls all `ready/` nodes with `nmap`/`ping`. Triggers `hostlost()` and leader failover when a node dies. |
| `fapilooper.sh` | Simple shell loop that restarts `fapi.py` inside the `flask` Docker container if it exits. |
| `heartbeatlooper.sh` | Shell loop that restarts `heartbeat.py`. |
| `diskref.sh` | Refreshes iSCSI target disks by calling `addtargetdisks.sh` + `iscsirefresh.sh`. |
| `zfsping.py`, `VolumeCheck.py`, `poolstoimport.py`, `selectspare.py`, `putzpool.py`, `allphysicalinfo.py` | **Hardware / ZFS loopers & utilities**. Handle disk failure detection, spare selection, pool import, volume health checks, physical disk enumeration. |
| `croncall.py`, `croncalllooper.sh` | Cron bridge: translates etcd snapshot schedules into system crontab entries. |
| `diskchange.sh`, `diskreflooper.sh` | Detect and react to disk hot-plug events. |
| `rebootmepls.sh`, `rebootmeplslooper.sh` | Handles queued reboot requests from the cluster. |
| `usersyncall.py`, `groupsyncall.py` | Bulk user/group synchronization helpers called by `checksyncs.py`. |

### 2.3 `/topstorweb` — React Frontend

| Path | Purpose |
|------|---------|
| `package.json` | Vite-based React 18 project. Uses Tailwind CSS, Axios, Lucide icons. |
| `src/App.jsx` | Root React component. |
| `src/Q*.jsx` | Page components: `QLogin`, `QDisks`, `QUsers`, `QGroups`, `QNfs`, `QCifs`, `QIscsi`, `QHomeFolders`, `QSnapshots`, `QNodes`, `QPartners`, `QLogs`, `QUpdates`, `QServicePerformance`, `QReceived`, `QSender`, `QUserPrivileges`. |
| `src/api/*.js` | API client modules: `auth.js`, `client.js`, `users.js`, `groups.js`, `volumes.js`, `pools.js`, `nodes.js`, `partners.js`, `logs.js`, `software.js`, `performance.js`, `notifications.js`. |
| `src/components/*.jsx` | Reusable components: buttons, dropdowns, inputs, node cards, forms. |
| `build_react/` | Production build output mounted into the `httpd` Docker container. |
| `dashboarddev3/` | Legacy AdminLTE dashboard (older UI generation). |
| `js/`, `netdata/`, `ar/` | Legacy static assets and Netdata dashboard files. |

---

## 3. Key Architecture Concepts

### 3.1 etcd Data Model

All cluster state lives in etcd. Key prefixes observed:

| Prefix | Meaning |
|--------|---------|
| `leader`, `leaderip` | Current cluster leader identity and IP. |
| `clusternode`, `clusternodeip` | This node's identity and IP. |
| `ready/<host>` | Nodes that have finished initialization. |
| `ActivePartners/<host>` | Active cluster members (including replication partners). |
| `possible/<host>` | Nodes requesting to join the cluster. |
| `pool/`, `pools/`, `volume/`, `vol/` | ZFS pool and volume configuration. |
| `usersinfo/`, `group/`, `usersigroup/` | Unix users, groups, and associations. |
| `sync/` | **Synchronization queue**. Entries follow patterns like `sync/<type>/<operation>_<args>/request` and `sync/<type>/<operation>_<args>/request/<node>`. |
| `notification/` | System alerts / events. |
| `cversion/<host>` | Installed software version per node. |
| `dirty/pool`, `dirty/volume` | Flags indicating stale state that needs refresh. |
| `host/current` | Current hardware inventory (disks, raids). |

### 3.2 Command Dispatch (`postchange`)

When the Flask API receives a mutating request (e.g., create volume):

1. API validates input (IPs, names, auth token).
2. Builds a command string pointing to a `/TopStor/*.py` or `*.sh` script.
3. Calls `postchange(cmdstring, owner_host)`.
4. `postchange` wraps the command in a JSON message and uses `sendhost()` (RabbitMQ) to deliver it to the target node's `topstorremote` / `topstorremoteack` listener.
5. The target node executes the script, which typically updates ZFS, `targetcli`, `smb.conf`, or etcd.
6. The script then writes a `sync/` entry so other nodes pick up the change via `checksyncs.py`.

### 3.3 Synchronization Engine (`checksyncs.py`)

`checksyncs.py` is the cluster's eventual-consistency engine.

**Sync Types:**
- `syncanitem`: Config items like `tz`, `ntp`, `gw`, `dns`, `bond`, `ipaddr`, `namespace`, `cron`, `log`, `priv`, etc.
- `wholeetcd`: Large config trees like `pool`, `volumes`, `ports`, `known`, etc.
- `etcdonly`: Small etcd-only keys like `alias`, `ready`, `configured`.
- `special1`: Password changes (`passwd`).
- `replisyncs`: User/group changes that must propagate to replication partners.

**Modes:**
- `syncinit` (leader only): Creates `sync/<type>/initial/request` entries so every node knows it must perform an initial sync of that type.
- `syncrequest` (all nodes): Polls etcd for pending `sync/.../request` entries, executes the corresponding action, then marks itself done (`sync/.../request/<node>`).
- `syncall` (joining node): Performs both initial syncs and pending request syncs.
- `replisyncrequest`: Special mode for replication partners (pulls syncs over a non-standard etcd port).

**Reboot Handling:**
- Bond changes can set a global `REBOOT_REQUIRED = True`. After all syncs complete, `_reboot_if_required()` triggers a system reboot.

### 3.4 Heartbeat & Failover (`heartbeat.py`)

- Runs continuously on every node.
- Polls all `ready/` nodes every second using `nmap` (port 2379) and falls back to `ping`.
- If a node is unreachable:
  - `hostlost(host, hostip)` is called.
  - The dead node is removed from `ready/`, `running/`, `known/`, `vol/`, `pools/`.
  - If the **leader** died, the `nextlead/er` node promotes itself via `leaderlost.sh`, updates etcd, and becomes the new leader.
- `getnextlead()` reads `nextlead/er` from etcd; if empty, sets itself as next leader.

### 3.5 Docker Containers

Each node runs the following containers (managed by `docker_setup.sh`):

| Container | Image | Role |
|-----------|-------|------|
| `etcd` | `moataznegm/quickstor:etcd` | Cluster configuration store. Exposes port 2379. |
| `etcdclient` | `moataznegm/quickstor:etcdclient` | Helper with etcd tools; mounts `/TopStor` and `/pace`. |
| `flask` | `moataznegm/quickstor:flask3` | Runs `fapi.py` on port 5001. |
| `httpd` | `moataznegm/quickstor:git` | Apache serving React UI on 80/443/19999/81. |
| `httpd_local` | (same) | Temporary forwarder on port 8080 during leader init. |
| `intdns` | `moataznegm/quickstor:dns` | Internal DNS at `10.11.12.7`. |
| `intsmb` | `moataznegm/quickstor:smb` | Samba container for CIFS shares. |
| `wetty` | `wettyoss/wetty` | Web-based SSH terminal on port 3000. |
| `promexport` | `prom/node-exporter` | Prometheus node metrics on port 9100. |
| `promcadvisor` | `gcr.io/cadvisor/cadvisor` | Container metrics on port 9101. |
| `promgraf` | `grafana/grafana` | **Leader only**. Grafana on port 4000. |
| `software` | `moataznegm/quickstor:git` | Legacy software repo container. |

### 3.6 Networking

- **Node IP**: `mynode` bond interface (e.g., `10.11.11.x/24`).
- **Cluster IP**: `mycluster` bond interface (e.g., `10.11.11.250/24` or same as node IP on non-primary).
- **Data IPs**: Additional bonds for storage traffic.
- **Internal DNS**: `10.11.12.7` (bridge network).
- **Firewall**: `firewall-cmd` opens NFS, RPC, Samba, iSCSI, etcd, RabbitMQ, and custom ports 2381-2481.

---

## 4. Common Development Tasks

### 4.1 Adding a New API Endpoint

1. Open `/TopStor/fapi.py`.
2. Add a new `@app.route('/api/v1/...', methods=[...])` decorated function.
3. Use `@login_required` if authentication is required.
4. Validate inputs with `is_valid_ip()`, `is_unique_ip()`, `is_unique_name()`.
5. Build a command string pointing to a `/TopStor/*.py` action script.
6. Call `postchange(cmndstring, owner_host)` to dispatch.
7. Add the corresponding React page/component in `/topstorweb/src/Q*.jsx` and API module in `/topstorweb/src/api/*.js`.

### 4.2 Adding a New Sync Type

1. Open `/pace/checksyncs.py`.
2. Add the sync key to the appropriate list (`syncanitem`, `wholeetcd`, `etcdonly`, `special1`).
3. In `doinitsync()` or `syncrequest()`, add a branch to handle the new sync key.
4. If the sync requires a system command, construct `cmdline` and run it via `subprocess.check_output()`.
5. If the sync requires etcd key mirroring, use `synckeys(leaderip, myhostip, key, key)`.

### 4.3 Restarting Services After Code Changes

```bash
# Restart Flask API
/pace/fapilooper.sh          # or inside docker: docker exec flask /TopStor/fapi.py

# Restart heartbeat
/pace/heartbeatlooper.sh

# Rebuild React UI (using the standard rebuild script)
/TopStor/rebuild_react.sh
# Restart Apache
/TopStor/httpdflask.sh <leaderip> no

# Re-run node setup (careful — resets state)
/TopStor/docker_setup.sh [init|local|restart|reset|stop|reboot]
```

### 4.4 Debugging Tips

- **Logs**: Check `/root/dockerlogs.txt`, `/root/checksync`, `/root/heartproblem`, `/TopStordata/tempdata`, `/TopStordata/volcreate`.
- **Etcd inspection**: `docker exec etcdclient /pace/etcdget.py <leaderip> <key> [--prefix]`
- **Flask debug**: `docker exec flask cat /TopStordata/tempdata` shows dispatched messages.
- **iSCSI debug**: `/root/iscsiwatch` tracks watchdog cycles.
- **Sync debug**: Run `/pace/checksyncs.py syncrequest <leaderip> <myhost>` manually and watch stdout.
- **Message codes**: `/TopStor/msgsglobal.txt` maps codes like `Lognsu0` to human-readable templates.

### 4.5 Committing, Pushing, and Pulling Code Versions

TopStor uses three on-disk Git repositories that must stay in sync across the cluster:

- `/TopStor`
- `/pace`
- `/topstorweb`

#### Pushing local changes

To commit all local changes in `/TopStor`, `/pace`, and `/topstorweb` and push them to the remote repository under a new or existing version branch:

```bash
/TopStor/systempush.sh <VersionName>
```

What it does:
1. Runs `git add --all`, removes `__py*` cache directories, commits, and pushes the branch in `/TopStor`, `/pace`, and `/topstorweb`.
2. Writes `sync/cversion/_<VersionName>__/request` keys into etcd so the rest of the cluster is notified of the new version.
3. Calls `/TopStor/myrepopush.sh <VersionName>`.

> A valid `<VersionName>` must be more than 3 characters long.

#### Pulling a remote version

To fetch and check out a remote branch on the local node for all three repositories:

```bash
/TopStor/systempull.sh <VersionName>
```

What it does:
1. Fetches the branch from origin in `/TopStor`, `/pace`, and `/topstorweb`.
2. Resets each repository to the remote branch state (removes local changes and `__py*` cache directories).
3. Updates etcd `sync/cversion/...` keys and runs `/TopStor/getcversion.sh` so the node reports the new version.
4. Executes `/TopStor/pre_apply.sh` if the pulled branch ships one.

> Use `samebranch` as `<VersionName>` to pull the branch that is currently checked out locally.

---

## 5. Important Files Cheat Sheet

| Concern | Files |
|---------|-------|
| API | `/TopStor/fapi.py` |
| Node Init | `/TopStor/docker_setup.sh`, `/TopStor/docker_primary.sh` |
| Push Code Version | `/TopStor/systempush.sh` |
| Pull Code Version | `/TopStor/systempull.sh` |
| Sync Engine | `/pace/checksyncs.py` |
| Heartbeat | `/pace/heartbeat.py`, `/pace/heartbeatlooper.sh` |
| API Looper | `/pace/fapilooper.sh` |
| iSCSI Watchdog | `/TopStor/iscsiwatchdog.sh` |
| Disk Refresh | `/pace/diskref.sh`, `/pace/diskchange.sh` |
| React Frontend | `/topstorweb/src/App.jsx`, `/topstorweb/src/Q*.jsx`, `/topstorweb/src/api/*.js` |
| Etcd Wrappers | `/TopStor/etcdget.py`, `/TopStor/etcdput.py`, `/TopStor/etcddel.py` (and `/pace/*local*` variants) |
| Messaging | `/TopStor/sendhost.py` |
| Logging | `/TopStor/logmsg.py`, `/TopStor/msgsglobal.txt` |
| Apache Config | `/TopStor/httpd_template.conf`, `/TopStor/topstorwebetc/httpd.conf` |
| TLS | `/TopStor/topstorwebetc/TopStor.crt`, `/TopStor/topstorwebetc/TopStor.key` |

---

## 6. Glossary

| Term | Meaning |
|------|---------|
| **Leader** | The primary node that owns the authoritative etcd IP (`10.11.11.250` by convention) and runs Grafana. |
| **Primary** | Same as leader in the context of `docker_setup.sh` (`isprimary=1`). |
| **Owner** | The node that physically hosts the ZFS pool / volume being acted upon. |
| **Sync** | Propagation of a configuration change across all (or a subset of) cluster nodes via etcd `sync/` keys. |
| **Postchange** | The API-side command dispatch mechanism using RabbitMQ (`sendhost`). |
| **Looper** | A shell script that infinitely restarts a Python daemon if it crashes. |
| **Watchdog** | A daemon that monitors hardware or service state and reacts to changes. |
| **Dirty** | A flag indicating that cached state (pools, volumes) is stale and should be refreshed. |
