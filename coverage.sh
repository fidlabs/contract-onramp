#!/bin/bash

set -euo pipefail

forge clean
forge build
forge coverage --report summary --report lcov
genhtml lcov.info -o report --rc derive_function_end_line=0
xdg-open report/index.html
