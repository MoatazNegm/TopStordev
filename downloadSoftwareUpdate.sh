#!/bin/bash

UPDATE_DEST="/TopStordata/"
LOGFILE="/var/log/update_script.log"

log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

download_http() {
    URL=$1
    DEST=$2
    log "Downloading update from $URL..."
    # QSD5.352 r2: the zfs node image has no wget (curl is used); curl -f so an HTTP error page is not saved as the package
    wget -O "$DEST/update.tar.gz" "$URL" || curl -fL -o "$DEST/update.tar.gz" "$URL" || error_exit "Failed to download from HTTP."
}

download_nfs() {
    SERVER=$1
    LOCATION=$2
    VERSION=$3
    MOUNT_POINT="/mnt/nfs_update"

    log "Mounting NFS share from $SERVER..."
    mkdir -p $MOUNT_POINT
    mount -t nfs "$SERVER:/$LOCATION" "$MOUNT_POINT" || error_exit "Failed to mount NFS."

    log "Searching for update file with version $VERSION..."
    FILE=$(find "$MOUNT_POINT" -type f -name "*${VERSION}*" | head -n 1)
    [[ -z "$FILE" ]] && error_exit "No update file found for version $VERSION on NFS."

    log "Copying update file $FILE..."
    cp "$FILE" "$UPDATE_DEST" || error_exit "Failed to copy file from NFS."

    log "Unmounting NFS..."
    umount "$MOUNT_POINT"
    rm -rf "$MOUNT_POINT"
}

download_cifs() {
    SERVER=$1
    LOCATION=$2
    VERSION=$3
    USERNAME=$4
    PASSWORD=$5
    MOUNT_POINT="/mnt/cifs_update"

    # QSD5.352 r2 (validator R5): an SMB path is //<server>/<share>[/<dir>] ("//$SERVER:/$LOCATION" was the NFS form and
    # never mounted).  Without the mount.cifs helper (cifs-utils) the mount cannot work: the zfs node image (container
    # flavour) has none, so the fetch stops at once with a clear reason instead of trying (no packages are installed).
    if ! command -v mount.cifs >/dev/null 2>&1 && [ ! -x /sbin/mount.cifs ] && [ ! -x /usr/sbin/mount.cifs ]; then
        [ -f /TopStor/flavor.sh ] && . /TopStor/flavor.sh
        if is_container 2>/dev/null; then
            error_exit "Failed to mount CIFS: no mount.cifs (cifs-utils) in the container flavour node image; SMB fetch is not available here, use http or nfs."
        fi
        error_exit "Failed to mount CIFS: no mount.cifs (cifs-utils) on this node."
    fi
    log "Mounting CIFS share //$SERVER/$LOCATION..."
    mkdir -p "$MOUNT_POINT"
    mount -t cifs "//$SERVER/$LOCATION" "$MOUNT_POINT" -o username="$USERNAME",password="$PASSWORD" || error_exit "Failed to mount CIFS."

    log "Searching for update file with version $VERSION..."
    FILE=$(find "$MOUNT_POINT" -type f -name "*${VERSION}*" | head -n 1)
    [[ -z "$FILE" ]] && error_exit "No update file found for version $VERSION on CIFS."

    log "Copying update file $FILE..."
    cp "$FILE" "$UPDATE_DEST" || error_exit "Failed to copy file from CIFS."

    log "Unmounting CIFS..."
    umount "$MOUNT_POINT"
    rm -rf "$MOUNT_POINT"
}

download_local() {
    SOURCE=$1
    log "Copying update from local source $SOURCE..."
    cp -r "$SOURCE"/* "$UPDATE_DEST" || error_exit "Failed to copy from local path."
}

# Main script execution
if [[ "$1" == "--source-type" && -n "$2" && "$3" == "--source" && -n "$4" ]]; then
    TYPE=$2
    SOURCE=$4
    VERSION=$6
    LOCATION=$8
    # Initialize optional variables
    CIFS_USERNAME=""
    CIFS_PASSWORD=""

    # Parse optional CIFS credentials
    if [[ "$TYPE" == "cifs" ]]; then
        if [[ "$9" == "--username" && -n ${10} && "${11}" == "--password" && -n "${12}" ]]; then
            CIFS_USERNAME=${10}
            CIFS_PASSWORD=${12}
        else
            error_exit "CIFS requires --username and --password."
        fi
    fi

    if [[ "$TYPE" == "cifs" || "$TYPE" == "nfs" ]]; then
	if [[ "$7" == "--location" && -n "$8" ]]; then
	    LOCATION=$8
        else 
	    error_exit "$TYPE requires --location" 
	fi
    fi

    mkdir -p "$UPDATE_DEST"

    case $TYPE in
        http)
            download_http "$SOURCE" "$UPDATE_DEST"
            ;;
        nfs)
            download_nfs "$SOURCE" "$LOCATION" "$VERSION"
            ;;
        cifs)
            download_cifs "$SOURCE" "$LOCATION" "$VERSION" "$CIFS_USERNAME" "$CIFS_PASSWORD"
            ;;
        local)
            download_local "$SOURCE"
            ;;
        *)
            error_exit "Unsupported source type: $TYPE"
            ;;
    esac

    log "Update process completed successfully."
else
    echo "Usage: $0 --source-type <http|nfs|cifs|local> --source <path_or_url> --version <version> [--username <username> --password <password>]"
    exit 1
fi
