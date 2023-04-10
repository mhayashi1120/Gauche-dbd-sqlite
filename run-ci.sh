#!/bin/sh

set -eu

./configure --enable-werror
make check
make do-sample
