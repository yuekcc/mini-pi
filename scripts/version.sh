#!/bin/bash

VERSION=$(git rev-parse HEAD)
echo "const String VERSION = \"0.0.1-${VERSION}\";"
