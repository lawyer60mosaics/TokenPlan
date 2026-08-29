#!/bin/sh
set -eu
umask 077

database=/var/lib/tokenplan/tokenplan.db
backup_dir=/var/backups/tokenplan

mkdir -p "$backup_dir"
if [ ! -f "$database" ]; then
    exit 0
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
target="$backup_dir/tokenplan-$timestamp.db"
sqlite3 "$database" ".backup '$target'"
gzip "$target"
find "$backup_dir" -type f -name 'tokenplan-*.db.gz' -mtime +14 -delete
