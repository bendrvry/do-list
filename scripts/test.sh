#!/bin/zsh
# Runs the StillCore test suite (Swift Testing).
#
# With only the Command Line Tools installed, the Swift Testing macro plugin and
# framework live outside the default search paths, and the newest SDK expects SwiftUI
# macro plugins that ship only with Xcode — so point at both explicitly.
set -e
cd "$(dirname "$0")/.."
CLT=$(xcode-select -p)
if [[ "$CLT" == *CommandLineTools* ]]; then
  if [[ -z "${SDKROOT:-}" ]]; then
    for sdk in "$CLT/SDKs/MacOSX26.5.sdk" "$CLT/SDKs/MacOSX26.sdk"; do
      if [[ -d "$sdk" ]]; then export SDKROOT="$sdk"; break; fi
    done
  fi
  swift test \
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
    -Xswiftc -F -Xswiftc "$CLT/Library/Developer/Frameworks" \
    -Xlinker -F -Xlinker "$CLT/Library/Developer/Frameworks" \
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/Frameworks" "$@"
else
  swift test "$@"
fi
