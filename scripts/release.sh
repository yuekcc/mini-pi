#!/bin/bash

set -ex

rm -rf build
c3c build --trust=full -O2 -D RELEASE
