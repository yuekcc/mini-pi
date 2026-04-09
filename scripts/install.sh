#!/bin/bash

set -ex

c3c build --trust=full -O2
cp build/mp.exe /D/app/mp-agent
cp libcurl-x64.dll /D/app/mp-agent
