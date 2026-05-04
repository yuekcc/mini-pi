#!/bin/bash

VERSION=$(git rev-parse HEAD)
echo "const String VERSION = \"1.0.0-${VERSION}\";"
