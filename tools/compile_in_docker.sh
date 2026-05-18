#!/bin/sh
set -e

if [ ! -d /work/assets/ipadic ]; then
  echo "assets/ipadic missing — stage IPADIC first" >&2
  exit 1
fi

apt-get update -qq >/dev/null
apt-get install -y -qq --no-install-recommends mecab mecab-utils

mkdir -p /work/assets/user_dict

# mecab-utils installs mecab-dict-index to /usr/lib/mecab/, not on PATH.
/usr/lib/mecab/mecab-dict-index \
  -d /work/assets/ipadic \
  -u /work/assets/user_dict/user.dic \
  -f utf-8 \
  -t utf-8 \
  /work/tools/user_gikun.csv

ls -l /work/assets/user_dict/user.dic
