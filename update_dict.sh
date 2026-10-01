#!/bin/sh
# POSIX sh: also run with `dash update_dict.sh <base-url>` in iOS a-Shell.
# Only curl and standard Unix text/file commands are required.
set -eu
cd "$(dirname "$0")"

BASE_URL=${1:-}
BASE_URL=${BASE_URL%/}
if [ -z "$BASE_URL" ]; then
    echo "Usage: sh update_dict.sh <rime-word-marker-base-url>" >&2
    exit 1
fi

# Keep temporary files on the same filesystem, so each mv is atomic.
umask 077
WORK_DIR=".update-dict.$$"
mkdir "$WORK_DIR"
FILES="dicts/rime_word_marker_export.dict.yaml dicts/rime_ice.cn_en_double_pinyin.txt opencc/rime_word_marker_export.opencc.txt rime_mint.dict.yaml opencc/emoji.json"
COMMIT_STARTED=0
cleanup() {
    status=$?
    rollback_failed=0
    trap - 0 1 2 3 15
    if [ "$COMMIT_STARTED" = 1 ]; then
        # Restore the whole set if a replacement fails or is interrupted.
        for file in $FILES; do
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
mkdir -p "$WORK_DIR/dicts" "$WORK_DIR/opencc" "$WORK_DIR/backup/dicts" "$WORK_DIR/backup/opencc" "$WORK_DIR/absent/dicts" "$WORK_DIR/absent/opencc"

download() {
    curl -fsSL --connect-timeout 10 --max-time 300 "$1" -o "$2"
}

# Check the saved response instead of relying on a pipeline's last exit code.
download "$BASE_URL" "$WORK_DIR/index"
if ! grep -q 'Rime' "$WORK_DIR/index"; then
    echo "FATAL: not a rime-word-marker server" >&2
    exit 1
fi

echo "Updating rime dict ..."
MAIN_DICT="dicts/rime_word_marker_export.dict.yaml"
CN_EN="dicts/rime_ice.cn_en_double_pinyin.txt"
OPENCC="opencc/rime_word_marker_export.opencc.txt"
download "$BASE_URL/api/export?statuses=accepted&include_weight=1&include_ai_assist=1&omit_yaml_header=0&export_mode=main&name=rime_word_marker_export" "$WORK_DIR/$MAIN_DICT"
download "https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/en_dicts/cn_en_double_pinyin.txt" "$WORK_DIR/upstream"
download "$BASE_URL/api/export?statuses=accepted&include_weight=0&include_ai_assist=1&omit_yaml_header=1&export_mode=mixed&mixed_scheme=ziranma&name=rime_word_marker_export" "$WORK_DIR/mixed"
download "$BASE_URL/api/export?statuses=accepted&include_weight=1&include_ai_assist=1&omit_yaml_header=0&export_mode=opencc&name=rime_word_marker_export" "$WORK_DIR/$OPENCC"

# A valid main export may contain no accepted entries; its header is mandatory.
grep -q '^name: *rime_word_marker_export[[:space:]]*$' "$WORK_DIR/$MAIN_DICT"
grep -q '^\.\.\.[[:space:]]*$' "$WORK_DIR/$MAIN_DICT"
validate_table() {
    # Reject HTML/error responses and malformed rows. Empty private tables are OK.
    awk '
        /^[[:space:]]*$/ || /^#/ { next }
        { if (index($0, "\t") == 0 || $0 ~ /^[[:space:]]*</) bad = 1 }
        END { exit bad ? 1 : 0 }
    ' "$1"
}
validate_table "$WORK_DIR/upstream"
test -s "$WORK_DIR/upstream"
validate_table "$WORK_DIR/mixed"
validate_table "$WORK_DIR/$OPENCC"
awk '
    /^\.\.\.[[:space:]]*$/ { body = 1; next }
    body && $0 !~ /^#/ && $0 !~ /^[[:space:]]*$/ {
        if (index($0, "\t") == 0 || $0 ~ /^[[:space:]]*</) bad = 1
    }
    END { exit bad ? 1 : 0 }
' "$WORK_DIR/$MAIN_DICT"

# awk prints a newline for every record, including an unterminated last line.
ORIGINAL_LINE_COUNT=$(awk 'END { print NR }' "$WORK_DIR/upstream")
CUSTOM_LINE_COUNT=$(awk 'END { print NR }' "$WORK_DIR/mixed")
awk '{ print }' "$WORK_DIR/upstream" "$WORK_DIR/mixed" > "$WORK_DIR/$CN_EN"

# Enable private data only after it exists. Do not overwrite user custom patches.
if grep -q '^[[:space:]]*- dicts/rime_word_marker_export[[:space:]]*$' rime_mint.dict.yaml; then
    cp rime_mint.dict.yaml "$WORK_DIR/rime_mint.dict.yaml"
else
    grep -q '^import_tables:[[:space:]]*$' rime_mint.dict.yaml
    sed '/^import_tables:[[:space:]]*$/a\
  - dicts/rime_word_marker_export
' rime_mint.dict.yaml > "$WORK_DIR/rime_mint.dict.yaml"
fi
if grep -q '"file": *"rime_word_marker_export.opencc.txt"' opencc/emoji.json; then
    cp opencc/emoji.json "$WORK_DIR/opencc/emoji.json"
else
    grep -q '^[[:space:]]*"file": *"others.txt"[[:space:]]*$' opencc/emoji.json
    sed '/^[[:space:]]*"file": *"others.txt"[[:space:]]*$/a\
                    },\
                    {\
                        "type": "text",\
                        "file": "rime_word_marker_export.opencc.txt"
' opencc/emoji.json > "$WORK_DIR/opencc/emoji.json"
fi

for file in $FILES; do
    if [ -f "$file" ]; then
        cp "$file" "$WORK_DIR/backup/$file"
    else
        : > "$WORK_DIR/absent/$file"
    fi
done
COMMIT_STARTED=1
for file in $FILES; do
    mv "$WORK_DIR/$file" "$file"
done
COMMIT_STARTED=0

echo
echo "===== Update completed ====="
echo "Path: $(pwd)"
echo "  Main dict: $(sed '1,/^\.\.\.[[:space:]]*$/d' "$MAIN_DICT" | wc -l) rows"
echo "  CN_EN dict: $ORIGINAL_LINE_COUNT upstream rows, $CUSTOM_LINE_COUNT custom rows"
echo "  OpenCC dict: $(wc -l < "$OPENCC") rows"
