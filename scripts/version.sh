#!/bin/bash

COMMIT_ID=$(git rev-parse --short HEAD)
echo "const String VERSION = \"1.0.0-${COMMIT_ID}\";"
