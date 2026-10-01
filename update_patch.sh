#!/bin/sh
set -eu
cd "$(dirname "$0")"

# jq is used only by this desktop helper, not by the iOS dictionary updater.
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 1; }
checksum() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{ print $1 }'
    else
        shasum -a 256 "$1" | awk '{ print $1 }'
    fi
}

umask 077
WORK_DIR=".update-patch.$$"
mkdir "$WORK_DIR"
INSTALL_FILES="melt_eng.schema.yaml"
COMMIT_STARTED=0
cleanup() {
    status=$?
    rollback_failed=0
    trap - 0 1 2 3 15
    if [ "$COMMIT_STARTED" = 1 ]; then
        for file in $INSTALL_FILES; do
            if [ -f "$WORK_DIR/backup/$file" ]; then
                mv "$WORK_DIR/backup/$file" "$file" || rollback_failed=1
            elif [ -f "$WORK_DIR/absent/$file" ]; then
                rm -f "$file" || rollback_failed=1
            fi
        done
    fi
    if [ "$rollback_failed" = 1 ]; then
        echo "FATAL: rollback incomplete; backups retained in $WORK_DIR" >&2
        exit 1
    fi
    rm -rf "$WORK_DIR"
    exit "$status"
}
trap cleanup 0
trap 'exit 1' 1 2 3 15
mkdir "$WORK_DIR/backup" "$WORK_DIR/absent"

curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/melt_eng.schema.yaml -o "$WORK_DIR/melt_eng.schema.yaml"
grep -q '^[[:space:]]*schema_id: *melt_eng[[:space:]]*$' "$WORK_DIR/melt_eng.schema.yaml"

MODEL="wanxiang-lts-zh-hans.gram"
curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS -o "$WORK_DIR/release.json"
jq -e --arg name "$MODEL" '.assets | map(select(.name == $name)) | if length == 1 then .[0] else error("model asset missing or ambiguous") end' "$WORK_DIR/release.json" > "$WORK_DIR/asset.json"
MODEL_URL=$(jq -er '.browser_download_url' "$WORK_DIR/asset.json")
MODEL_SIZE=$(jq -er '.size | select(type == "number" and . > 0 and . == floor)' "$WORK_DIR/asset.json")
MODEL_DIGEST=$(jq -er '.digest | select(type == "string")' "$WORK_DIR/asset.json")
printf '%s\n' "$MODEL_DIGEST" | grep -Eq '^sha256:[0-9a-f]{64}$'
MODEL_HASH=${MODEL_DIGEST#sha256:}
case "$MODEL_URL" in
    https://github.com/amzxyz/RIME-LMDG/releases/download/*) ;;
    *) echo "FATAL: unexpected model URL" >&2; exit 1 ;;
esac

valid_model() {
    [ -f "$1" ] && [ "$(wc -c < "$1" | tr -d '[:space:]')" = "$MODEL_SIZE" ] && [ "$(checksum "$1")" = "$MODEL_HASH" ]
}
if ! valid_model "$MODEL"; then
    curl -fsSL --connect-timeout 10 --max-time 1800 "$MODEL_URL" -o "$WORK_DIR/$MODEL"
    if ! valid_model "$WORK_DIR/$MODEL"; then
        echo "FATAL: model size or SHA-256 mismatch" >&2
        exit 1
    fi
    INSTALL_FILES="$INSTALL_FILES $MODEL"
fi

for file in $INSTALL_FILES; do
    if [ -f "$file" ]; then
        cp "$file" "$WORK_DIR/backup/$file"
    else
        : > "$WORK_DIR/absent/$file"
    fi
done
COMMIT_STARTED=1
for file in $INSTALL_FILES; do
    mv "$WORK_DIR/$file" "$file"
done
COMMIT_STARTED=0
echo "Patch update completed; language model size and SHA-256 verified."
