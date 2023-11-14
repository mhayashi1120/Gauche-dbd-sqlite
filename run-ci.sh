#!/bin/sh

set -eu

./configure --enable-werror
make check install validate
make do-sample
