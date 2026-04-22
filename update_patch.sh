#!/usr/bin/env bash
set -e
THIS_DIR=$( cd "$( dirname "${BASH_SOURCE[0]:-${(%):-%x}}" )" && pwd )
cd "$THIS_DIR"

wget https://raw.githubusercontent.com/iDvel/rime-ice/refs/heads/main/melt_eng.schema.yaml -O melt_eng.schema.yaml
test -f wanxiang-lts-zh-hans.gram || wget https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram -O wanxiang-lts-zh-hans.gram
