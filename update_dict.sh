#!/usr/bin/env bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
cd "$THIS_DIR"

# main dict
MAIN_DICT="dicts/rime_word_marker_export.dict.yaml"
curl 'http://sir0-z10.dxng.net:21234/api/export?statuses=accepted&include_weight=1&include_ai_assist=1&omit_yaml_header=0&include_mixed=0&mixed_scheme=full_pinyin&name=rime_word_marker_export' -o "$MAIN_DICT"
# CN_EN dict
CN_EN="dicts/rime_ice.cn_en_double_pinyin.txt"
curl https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/en_dicts/cn_en_double_pinyin.txt -o "$CN_EN"
ORIGINAL_LINE_COUNT=$(wc -l < "$CN_EN")
[[ $(tail -c1 "$CN_EN" | wc -l) -gt 0 ]] || echo "" >> "$CN_EN"
curl -fsSL 'http://sir0-z10.dxng.net:21234/api/export?statuses=accepted&include_weight=0&include_ai_assist=1&omit_yaml_header=1&include_mixed=1&mixed_scheme=ziranma&name=rime_word_marker_export' >> "$CN_EN"

# Summary
echo
echo "===== Update completed ====="
echo "Path: $(pwd)"
echo "Summary:"
echo "  Main dict:  $(sed '1,/^\.\.\.$/d' "$MAIN_DICT" | wc -l) entries"
echo "  CN_EN dict: $ORIGINAL_LINE_COUNT original entries"
echo "              $(($(wc -l < "$CN_EN") - ${ORIGINAL_LINE_COUNT})) custom entries"
