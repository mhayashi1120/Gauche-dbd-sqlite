#!/bin/bash

set -eu

echo "This script is intended to be invoked from top directory."

WORK_DIR=`mktemp --directory`

echo "Working on ${WORK_DIR}"

git checkout-index --all --force --prefix "${WORK_DIR}/"

# apply working copy changes
git diff . | patch --strip 1 --directory "${WORK_DIR}"

cd "${WORK_DIR}"

docker run -v ${WORK_DIR}:/home/app --rm -ti practicalscheme/gauche sh -c 'cd /home/app && ./_docker/setup.sh && ./run-ci.sh'

rm -rf "${WORK_DIR}"
