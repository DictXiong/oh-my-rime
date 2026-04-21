#!/usr/bin/env bash
set -e

# 3rd-party
wget https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/melt_eng.schema.yaml -O melt_eng.schema.yaml
wget https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/en_dicts/cn_en_double_pinyin.txt -O dicts/rime_ice.cn_en_double_pinyin.txt
test -f wanxiang-lts-zh-hans.gram || wget https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram -O wanxiang-lts-zh-hans.gram

# user dict
wget 'http://sir0-z10.dxng.net:21234/api/export?statuses=accepted&include_weight=1&include_ai_assist=1&name=rime_word_marker_export' -O dicts/rime_word_marker_export.dict.yaml
