#!/bin/bash

set -ex

sh scripts/release.sh
cp build/mp.exe /D/app/mp-agent
cp libcurl-x64.dll /D/app/mp-agent
