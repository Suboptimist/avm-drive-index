#!/bin/bash
#
# Drive Indexer
# -------------
# Keeps the "Drive Index" folder up to date with every external storage
# drive connected to this Mac. SD cards and mounted disk images (such as
# app installers) are intentionally ignored. For each drive it creates:
#
#   Drive Index/Drives/<Drive Name>/
#       _DRIVE INFO.txt      size, format, last connected, last used by,
#                            and a connection history
#       <mirrored folders>   the drive's folder structure, browsable in
#                            Finder (folders only, no files, 3 levels deep)
#
# and it keeps "Drive Index/Drives Overview.txt" as a one-glance summary.
#
# Normally this is run automatically by the LaunchAgent that
# "Install Drive Indexer.command" sets up, but it is safe to run by hand
# at any time.

set -u

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX_DIR="${DRIVE_INDEX_DIR:-$HOME/Library/Application Support/AVM Drive Index}"
DRIVES_DIR="$INDEX_DIR/Drives"
OVERVIEW="$INDEX_DIR/Drives Overview.txt"
STATE_DIR="$INDEX_DIR/.mounted"
INFO_NAME="_DRIVE INFO.txt"

MAX_DEPTH=3        # how many folder levels deep to mirror
MAX_FOLDERS=1000   # safety cap so a huge drive can't create endless folders
FILE_DEPTH=6       # how deep to record file names
MAX_FILES=20000    # safety cap on file names recorded per drive
MAX_HISTORY=50     # connection-history lines to keep per drive

mkdir -p "$DRIVES_DIR" "$STATE_DIR"

CONSOLE_USER="$(stat -f%Su /dev/console 2>/dev/null || echo "${USER:-unknown}")"
NOW="$(date "+%Y-%m-%d %H:%M")"

CURRENT_IDS=""     # drive ids seen mounted during this run
CONNECTED_NOW=""   # index-folder names of drives connected right now

for vol in /Volumes/*; do
    [ -e "$vol" ] || continue
    [ -L "$vol" ] && continue                    # skip "Macintosh HD" symlink

    # `diskutil` can make a mounted .dmg look like an ordinary external HFS
    # volume. `hdiutil` is the authoritative source for DiskImages mounts,
    # so exclude every mounted disk image before considering the volume.
    if /usr/bin/hdiutil info 2>/dev/null | grep -Fq "$(printf '\t%s' "$vol")"; then
        continue
    fi

    info="$(diskutil info "$vol" 2>/dev/null)" || continue

    removable="$(printf '%s\n' "$info" | sed -n 's/.*Removable Media: *//p')"
    location="$(printf '%s\n' "$info"  | sed -n 's/.*Device Location: *//p')"
    case "$removable|$location" in
        *Removable*|*External*) ;;               # candidate external storage volume
        *) continue ;;                           # skip internal volumes
    esac

    # App installers are commonly mounted .dmg disk images. They can report
    # themselves as external/removable, so exclude disk-image volumes first.
    disk_image="$(printf '%s\n' "$info" | sed -n 's/.*Disk Image: *//p')"
    virtual="$(printf '%s\n' "$info"    | sed -n 's/.*Virtual: *//p')"
    case "$disk_image|$virtual" in
        *Yes*) continue ;;
    esac

    # SD cards connected through a reader can identify the mounted volume as
    # USB. Inspect the parent device as well, where macOS exposes the card or
    # card-reader metadata.
    whole="$(printf '%s\n' "$info" | sed -n 's/.*Part of Whole: *//p')"
    media_info=""
    [ -n "$whole" ] && media_info="$(diskutil info "$whole" 2>/dev/null || true)"
    media_details="$(printf '%s\n%s\n' "$info" "$media_info" | sed -n \
        '/Protocol:/p; /Device \/ Media Name:/p; /Media Name:/p; /Media Type:/p')"
    if printf '%s\n' "$media_details" | grep -Eiq \
        'Protocol: *(Secure Digital|SD|SD/MMC)|((Device / )?Media Name|Media Type):.*(SD Card|SD/MMC|Card Reader)'; then
        continue
    fi

    name="$(basename "$vol")"
    uuid="$(printf '%s\n' "$info" | sed -n 's/.*Volume UUID: *//p')"
    fs="$(printf '%s\n' "$info"   | sed -n 's/.*File System Personality: *//p')"
    size="$(printf '%s\n' "$info" | sed -n 's/.*Disk Size: *\([^(]*\)(.*/\1/p' | sed 's/ *$//')"

    # A stable id per drive: the volume UUID, or the name if there is none.
    id="${uuid:-$name}"
    id="${id// /_}"

    # Pick the index folder for this drive. If a *different* drive with the
    # same name was indexed before, use "Name (2)", "Name (3)", ...
    target="$DRIVES_DIR/$name"
    n=1
    while [ -f "$target/$INFO_NAME" ]; do
        existing="$(sed -n 's/^UUID: *//p' "$target/$INFO_NAME")"
        if [ -z "$existing" ] || [ -z "$uuid" ] || [ "$existing" = "$uuid" ]; then
            break
        fi
        n=$((n + 1))
        target="$DRIVES_DIR/$name ($n)"
    done

    # Is this a fresh connection, or just a re-scan while still plugged in?
    statefile="$STATE_DIR/$id"
    new_connection=0
    [ -f "$statefile" ] || new_connection=1
    touch "$statefile"
    CURRENT_IDS="$CURRENT_IDS $id "
    CONNECTED_NOW="$CONNECTED_NOW|$(basename "$target")|"

    # Carry over the connection history from the previous info file.
    history=""
    if [ -f "$target/$INFO_NAME" ]; then
        history="$(sed -n '/^CONNECTION HISTORY/,$p' "$target/$INFO_NAME" | tail -n +2)"
    fi
    if [ $new_connection -eq 1 ]; then
        if [ -n "$history" ]; then
            history="$NOW — $CONSOLE_USER
$history"
        else
            history="$NOW — $CONSOLE_USER"
        fi
    fi
    history="$(printf '%s\n' "$history" | grep -v '^$' | head -n $MAX_HISTORY)"

    last_line="$(printf '%s\n' "$history" | head -n 1)"
    last_connected="${last_line%% — *}"
    last_user="${last_line#* — }"

    # Rebuild the mirrored folder structure: wipe old folders (files such
    # as the info file are kept), then recreate what is on the drive now.
    mkdir -p "$target"
    find "$target" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null

    folder_count=0
    truncated=0
    unreadable=0
    if ls "$vol" >/dev/null 2>&1; then
        while IFS= read -r dir; do
            rel="${dir#"$vol"/}"
            folder_count=$((folder_count + 1))
            if [ $folder_count -gt $MAX_FOLDERS ]; then
                truncated=1
                folder_count=$MAX_FOLDERS
                break
            fi
            mkdir -p "$target/$rel"
        done < <(find "$vol" -mindepth 1 -maxdepth $MAX_DEPTH -type d \
                    -not -path '*/.*' -not -name '.*' \
                    -not -path '*/System Volume Information*' 2>/dev/null | sort)
    else
        unreadable=1
    fi

    folders_note="$folder_count folders (shown down to $MAX_DEPTH levels deep, files not included)"
    [ $truncated -eq 1 ]  && folders_note="$folders_note — drive has more; only the first $MAX_FOLDERS are shown"
    [ $unreadable -eq 1 ] && folders_note="could not read this drive's contents (macOS may need permission — see README)"

    # Record the drive's files (name + size) in "_FILE LIST.txt", one per
    # line as "size_in_bytes|relative/path". The app uses this for its
    # folder tree and search; the mirrored Finder folders stay folders-only.
    filelist="$target/_FILE LIST.txt"
    file_count=0
    files_note=""
    if [ $unreadable -eq 0 ]; then
        find "$vol" -mindepth 1 -maxdepth $FILE_DEPTH -type f \
            -not -path '*/.*' -not -name '.*' \
            -not -path '*/System Volume Information*' \
            -exec stat -f '%z|%N' {} + 2>/dev/null \
          | awk -v prefix="$vol/" '{
                i = index($0, "|")
                if (i == 0) next
                print substr($0, 1, i) substr($0, i + 1 + length(prefix))
            }' \
          | head -n $MAX_FILES > "$filelist"
        file_count=$(wc -l < "$filelist" | tr -d ' ')
        files_note="$file_count files listed (down to $FILE_DEPTH levels deep)"
        [ "$file_count" -ge $MAX_FILES ] && files_note="$files_note — drive has more; only the first $MAX_FILES are listed"
    else
        files_note="could not read this drive's contents"
    fi

    # How much room is left, as of right now. `df` is used rather than
    # `diskutil` because it reports the same way for every filesystem, and it
    # works even when the drive's contents cannot be listed.
    free_space=""
    used_percent=""
    df_line="$(df -k "$vol" 2>/dev/null | tail -1)"
    if [ -n "$df_line" ]; then
        # "<free space text>|<whole-number percent used>"
        df_out="$(printf '%s\n' "$df_line" | awk '{
            total = $2 * 1024; avail = $4 * 1024
            if (total <= 0) exit
            pct = (avail * 100) / total
            n = split("bytes KB MB GB TB PB", u, " ")
            v = avail; i = 1
            while (v >= 1000 && i < n) { v /= 1000; i++ }
            if (i == 1)          s = sprintf("%d %s (%.0f%% free)", v, u[i], pct)
            else if (v >= 100)   s = sprintf("%.0f %s (%.0f%% free)", v, u[i], pct)
            else                 s = sprintf("%.1f %s (%.0f%% free)", v, u[i], pct)
            printf "%s|%.0f", s, 100 - pct
        }')"
        if [ -n "$df_out" ]; then
            free_space="${df_out%%|*}"
            used_percent="${df_out##*|}"
        fi
    fi

    {
        echo "DRIVE:           $name"
        echo "SIZE:            ${size:-unknown}"
        echo "FREE SPACE:      ${free_space:-unknown}"
        echo "USED PERCENT:    ${used_percent}"
        echo "FORMAT:          ${fs:-unknown}"
        echo "UUID:            ${uuid:-none}"
        echo ""
        echo "LAST CONNECTED:  $last_connected"
        echo "LAST USED BY:    $last_user"
        echo ""
        echo "FOLDERS:         $folders_note"
        echo "FILES:           $files_note"
        echo ""
        echo "The folders next to this file mirror what is on the drive."
        echo "They are recreated automatically each time the drive is"
        echo "connected, so don't store anything of your own in them."
        echo ""
        echo "CONNECTION HISTORY (newest first, on this Mac):"
        printf '%s\n' "$history"
    } > "$target/$INFO_NAME"
done

# Forget drives that have been ejected, so their next connection is
# recorded as a new entry in the history.
for f in "$STATE_DIR"/*; do
    [ -e "$f" ] || continue
    fid="$(basename "$f")"
    case "$CURRENT_IDS" in
        *" $fid "*) ;;
        *) rm -f "$f" ;;
    esac
done

# Rebuild the one-glance overview, newest connection first.
rows=""
for d in "$DRIVES_DIR"/*/; do
    [ -f "$d/$INFO_NAME" ] || continue
    dn="$(basename "$d")"
    lc="$(sed -n 's/^LAST CONNECTED:  *//p' "$d/$INFO_NAME")"
    lu="$(sed -n 's/^LAST USED BY:  *//p' "$d/$INFO_NAME")"
    fr="$(sed -n 's/^FREE SPACE:  *//p' "$d/$INFO_NAME")"
    mark=""
    case "$CONNECTED_NOW" in *"|$dn|"*) mark="  ← connected right now" ;; esac
    rows="$rows$lc|$dn|$lu|$fr|$mark
"
done

{
    echo "EXTERNAL DRIVES — updated automatically whenever a drive is connected"
    echo "Last updated: $NOW"
    echo ""
    printf '%-30s %-18s %-22s %s\n' "DRIVE" "LAST CONNECTED" "FREE SPACE" "LAST USED BY"
    printf '%-30s %-18s %-22s %s\n' "-----" "--------------" "----------" "------------"
    printf '%s' "$rows" | grep -v '^$' | sort -r | while IFS='|' read -r lc dn lu fr mark; do
        printf '%-30s %-18s %-22s %s%s\n' "$dn" "$lc" "$fr" "$lu" "$mark"
    done
    echo ""
    echo "Open the \"Drives\" folder to browse each drive's folder structure."
} > "$OVERVIEW"

exit 0
