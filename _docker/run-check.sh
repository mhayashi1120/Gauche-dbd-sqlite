#!/bin/bash

set -eu

echo "This script is intended to be invoked from top directory."

WORK_DIR=`mktemp --directory`

git clone . "${WORK_DIR}"
cd "${WORK_DIR}"

docker run -v ${WORK_DIR}:/home/app --rm -ti practicalscheme/gauche sh -c 'cd /home/app && ./_docker/setup.sh && ./configure && make check'
