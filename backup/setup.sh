#!/usr/bin/env bash
# One-off setup for daily S3 backups of local/. Uses your admin AWS credentials
# (AWS_PROFILE or default) to deploy backup-infra.yaml, then stores the backup
# user's key in the macOS Keychain and schedules backup.sh with launchd.
# Safe to re-run: finished steps are skipped.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$HERE/backup.env"
STACK=claude-whatsapp-backup
SERVICE=claude-whatsapp-backup
LABEL=local.claude-whatsapp.backup
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/claude-whatsapp-backup.log"

[[ -f "$ENV_FILE" ]] || cp "$HERE/backup.env.example" "$ENV_FILE"
# shellcheck source=/dev/null
source "$ENV_FILE"
: "${BACKUP_REGION:=eu-west-2}"
: "${BACKUP_RETENTION_DAYS:=30}"
LOCAL_DIR="${LOCAL_DIR:-$HERE/../../local}"
LOCAL_DIR="$(cd "$LOCAL_DIR" && pwd)"

# Set KEY=value in backup.env, replacing any existing line.
set_env() {
  local tmp
  tmp="$(mktemp)"
  grep -v "^$1=" "$ENV_FILE" > "$tmp" || true
  echo "$1=$2" >> "$tmp"
  mv "$tmp" "$ENV_FILE"
}

echo "==> Deploying stack $STACK in $BACKUP_REGION"
aws cloudformation deploy --region "$BACKUP_REGION" --stack-name "$STACK" \
  --template-file "$HERE/backup-infra.yaml" --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "NoncurrentVersionDays=$BACKUP_RETENTION_DAYS" \
  --no-fail-on-empty-changeset

output() {
  aws cloudformation describe-stacks --region "$BACKUP_REGION" --stack-name "$STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
bucket="$(output BucketName)"
user="$(output UserName)"
set_env BACKUP_REGION "$BACKUP_REGION"
set_env BACKUP_RETENTION_DAYS "$BACKUP_RETENTION_DAYS"
set_env BACKUP_BUCKET "$bucket"
set_env LOCAL_DIR "$LOCAL_DIR"
echo "    bucket $bucket, user $user"

if security find-generic-password -s "$SERVICE" -a access-key-id >/dev/null 2>&1; then
  echo "==> Access key already in Keychain (service $SERVICE)"
else
  echo "==> Creating access key for $user and storing it in the Keychain"
  read -r key_id secret < <(aws iam create-access-key --user-name "$user" \
    --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
  security add-generic-password -U -s "$SERVICE" -a access-key-id -w "$key_id"
  security add-generic-password -U -s "$SERVICE" -a secret-access-key -w "$secret"
  unset secret
fi

echo "==> Scheduling daily backup ($PLIST)"
mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
sed -e "s|__LABEL__|$LABEL|" -e "s|__SCRIPT__|$HERE/backup.sh|" -e "s|__LOG__|$LOG|g" \
  "$HERE/launchd.plist.template" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "==> Done. Run the first backup now with: $HERE/backup.sh"
echo "    Log: $LOG"
