#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

mkdir -p dist
LOG_PATH="$PROJECT_ROOT/dist/preview-build.log"

echo "Building and testing the local version. Log: $LOG_PATH"
if ! (
    swift build &&
    swift test
) > "$LOG_PATH" 2>&1; then
    tail -n 70 "$LOG_PATH"
    echo "Build or tests failed. The installed app and task data were not changed." >&2
    exit 1
fi

tail -n 12 "$LOG_PATH"

# Request a normal quit so SwiftData can finish saving before the backup.
if pgrep -x EasyTODO >/dev/null; then
    echo "Asking the running EasyTODO app to quit before backing up its data."
    osascript <<'APPLESCRIPT'
if application id "com.easytodo.EasyTODO" is running then
    tell application id "com.easytodo.EasyTODO" to quit
end if
APPLESCRIPT

    for ((attempt = 0; attempt < 30; attempt++)); do
        if ! pgrep -x EasyTODO >/dev/null; then
            break
        fi
        sleep 0.2
    done

    if pgrep -x EasyTODO >/dev/null; then
        echo "EasyTODO is still running. Quit it manually, then run this script again." >&2
        exit 1
    fi
fi

BACKUP_DIR="$(mktemp -d "$PROJECT_ROOT/dist/data-backup-$(date +%Y%m%d-%H%M%S)-XXXXXX")"
SUPPORT_DIR="$HOME/Library/Application Support"

for directory in EasyTODO DesktopTodo; do
    if [[ -d "$SUPPORT_DIR/$directory" ]]; then
        ditto "$SUPPORT_DIR/$directory" "$BACKUP_DIR/$directory"
    fi
done

for suffix in "" "-shm" "-wal"; do
    if [[ -f "$SUPPORT_DIR/default.store$suffix" ]]; then
        cp -p "$SUPPORT_DIR/default.store$suffix" "$BACKUP_DIR/default.store$suffix"
    fi
done

if defaults read com.easytodo.EasyTODO >/dev/null 2>&1; then
    defaults export com.easytodo.EasyTODO "$BACKUP_DIR/preferences.plist"
fi

echo "Data backup: $BACKUP_DIR"
if ! CONFIGURATION=debug VERSION=1.0.4 BUILD_NUMBER=10401 bash scripts/package_app.sh >> "$LOG_PATH" 2>&1; then
    tail -n 70 "$LOG_PATH"
    echo "Packaging failed. The data backup and installed app are unchanged." >&2
    exit 1
fi

echo "Opening the source-built app: $PROJECT_ROOT/dist/EasyTODO.app"
echo "The app in /Applications has not been replaced. This preview uses the same task store."
open -n "$PROJECT_ROOT/dist/EasyTODO.app"
