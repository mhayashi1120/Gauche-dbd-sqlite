#!/bin/sh

set -eu

./configure
make check
make do-sample
