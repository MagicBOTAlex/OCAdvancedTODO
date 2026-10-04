#!/bin/sh
# Build the bundles and run every test.
set -e
cd "$(dirname "$0")"

python3 build.py

echo "== todo self-test =="
ocplay --timeout 60 tests/computer.yaml todo.lua --self-test

echo "== ui framework specs =="
ocplay --timeout 60 tests/computer.yaml tests/ui_test.lua
