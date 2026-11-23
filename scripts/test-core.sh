#!/bin/bash
# DoloopCore 테스트. Xcode 없이 명령줄 도구만 있을 때는 Swift Testing 매크로 경로를 직접 넘긴다.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
developer_dir="$(xcode-select -p)"
plugin_dir="$developer_dir/usr/lib/swift/host/plugins/testing"

args=()
if [[ "$developer_dir" == */CommandLineTools && -d "$plugin_dir" ]]; then
  args=(-Xswiftc -plugin-path -Xswiftc "$plugin_dir")
fi

exec swift test --package-path "$root/Packages/DoloopCore" ${args[@]+"${args[@]}"} "$@"
