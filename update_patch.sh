#!/usr/bin/env bash
set -e

# 3rd-party
wget https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/melt_eng.schema.yaml -O melt_eng.schema.yaml
CN_EN="dicts/rime_ice.cn_en_double_pinyin.txt"
wget https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/en_dicts/cn_en_double_pinyin.txt -O "$CN_EN"
[[ $(tail -c1 "$CN_EN" | wc -l) -gt 0 ]] || echo "" >> "$CN_EN"
test -f wanxiang-lts-zh-hans.gram || wget https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram -O wanxiang-lts-zh-hans.gram

# user dict
wget 'http://sir0-z10.dxng.net:21234/api/export?statuses=accepted&include_weight=1&include_ai_assist=1&omit_yaml_header=0&include_mixed=0&mixed_scheme=full_pinyin&name=rime_word_marker_export' -O dicts/rime_word_marker_export.dict.yaml
curl -fsSL 'http://sir0-z10.dxng.net:21234/api/export?statuses=accepted&include_weight=0&include_ai_assist=1&omit_yaml_header=1&include_mixed=1&mixed_scheme=ziranma&name=rime_word_marker_export' >> "$CN_EN"
