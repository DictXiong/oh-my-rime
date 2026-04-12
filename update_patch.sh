#!/usr/bin/env bash
set -e

wget https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/melt_eng.schema.yaml -O melt_eng.schema.yaml
wget https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/en_dicts/cn_en_double_pinyin.txt -O dicts/rime_ice.cn_en_double_pinyin.txt
test -f wanxiang-lts-zh-hans.gram || wget https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram -O wanxiang-lts-zh-hans.gram
