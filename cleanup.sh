#!/usr/bin/env bash

set -e

# Precalculate all of our paths, etc.
NOW=`date +%s`
NOW_STR=`date +%Y%m%d%H%M%S%z`
ROOT_DIR="/opt/wp-backup"
BACKUPS_ROOT_DIR="${ROOT_DIR}/backups"

echo "Starting cleanup of local backups..."
echo "Now:          ${NOW_STR} (${NOW})"
echo "Root:         ${ROOT_DIR}"
echo "Backups root: ${BACKUPS_ROOT_DIR}"
echo ""

# Perform cleanup
echo "Deleting all backups older than 1 week..."
find "${BACKUPS_ROOT_DIR}" -type f -name '*.tar.gz' -mtime +7 -exec rm {} \;
echo "Done deleting all backups older than 1 week."
echo ""

echo "Cleanup completed successfully."
