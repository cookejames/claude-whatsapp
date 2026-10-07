#!/usr/bin/env bash
# Sync local/ to the versioned S3 bucket. Runs daily from launchd (see setup.sh);
# safe to run by hand. Only changed files upload; S3 keeps the old versions.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$HERE/backup.env"
SERVICE=claude-whatsapp-backup

[[ -f "$ENV_FILE" ]] || { echo "backup: $ENV_FILE missing; run backup/setup.sh" >&2; exit 1; }
# shellcheck source=/dev/null
source "$ENV_FILE"
LOCAL_DIR="${LOCAL_DIR:-$HERE/../../local}"
: "${BACKUP_BUCKET:?BACKUP_BUCKET not set in $ENV_FILE; run backup/setup.sh}"
: "${BACKUP_REGION:=eu-west-2}"
[[ -d "$LOCAL_DIR" ]] || { echo "backup: $LOCAL_DIR not found" >&2; exit 1; }

keychain() { security find-generic-password -s "$SERVICE" -a "$1" -w 2>/dev/null; }

# Use only the backup user's keys, never a profile from ~/.aws.
unset AWS_PROFILE AWS_SESSION_TOKEN
AWS_ACCESS_KEY_ID="$(keychain access-key-id)" || { echo "backup: no access key in Keychain; run backup/setup.sh" >&2; exit 1; }
AWS_SECRET_ACCESS_KEY="$(keychain secret-access-key)" || { echo "backup: no secret key in Keychain; run backup/setup.sh" >&2; exit 1; }
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION="$BACKUP_REGION"

excludes=()
while IFS= read -r pattern; do
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  excludes+=(--exclude "$pattern")
done < "$HERE/excludes.txt"

echo "==> $(date '+%F %T') backup $LOCAL_DIR -> s3://$BACKUP_BUCKET/local/"
# Exit 2 means some files were skipped (sockets such as the WhatsApp server's,
# which S3 can't store, are always skipped with a warning); 1 means a real failure.
status=0
aws s3 sync "$LOCAL_DIR" "s3://$BACKUP_BUCKET/local/" \
  --delete --no-follow-symlinks --only-show-errors ${excludes[@]+"${excludes[@]}"} || status=$?
if (( status == 2 )); then
  echo "    (skipped files above are sockets or unreadable; everything else synced)"
elif (( status != 0 )); then
  echo "==> $(date '+%F %T') FAILED (aws exit $status)" >&2
  exit "$status"
fi
echo "==> $(date '+%F %T') done"
