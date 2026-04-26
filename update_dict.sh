#!/usr/bin/env bash
set -e
THIS_DIR=$(dirname "$0")
cd "$THIS_DIR"

BASE_URL="$1"
if [ -z "$BASE_URL" ]; then
    echo "FATAL: no rime-word-marker base url is given!"
    echo "Usage: ./update_dict.sh <base-url>"
    exit -1
fi

# main dict
MAIN_DICT="dicts/rime_word_marker_export.dict.yaml"
curl "$BASE_URL/api/export?statuses=accepted&include_weight=1&include_ai_assist=1&omit_yaml_header=0&export_mode=main&name=rime_word_marker_export" -o "$MAIN_DICT"
# CN_EN dict
CN_EN="dicts/rime_ice.cn_en_double_pinyin.txt"
curl https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/en_dicts/cn_en_double_pinyin.txt -o "$CN_EN"
ORIGINAL_LINE_COUNT=$(wc -l < "$CN_EN")
[ "$(tail -c1 "$CN_EN" | wc -l)" -gt 0 ] || echo "" >> "$CN_EN"
curl -fsSL "$BASE_URL/api/export?statuses=accepted&include_weight=0&include_ai_assist=1&omit_yaml_header=1&export_mode=mixed&mixed_scheme=ziranma&name=rime_word_marker_export" >> "$CN_EN"
# OpenCC dict
OPENCC="opencc/rime_word_marker_export.opencc.txt"
curl -fsSL "$BASE_URL/api/export?statuses=accepted&include_weight=1&include_ai_assist=1&omit_yaml_header=0&export_mode=opencc&name=rime_word_marker_export" -o "$OPENCC"

# Summary
echo
echo "===== Update completed ====="
echo "Path: $(pwd)"
echo "Summary:"
echo "  Main dict:   $(sed '1,/^\.\.\.$/d' "$MAIN_DICT" | wc -l) entries"
echo "  CN_EN dict:  $ORIGINAL_LINE_COUNT original entries"
echo "               $(($(wc -l < "$CN_EN") - ${ORIGINAL_LINE_COUNT})) custom entries"
echo "  OpenCC dict: $(wc -l < "$OPENCC") entries"
