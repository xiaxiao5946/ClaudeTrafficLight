#!/bin/bash
set -e

cd "$(dirname "$0")"

swiftc -parse-as-library \
  -target arm64-apple-macosx13.0 \
  Sources/ClaudeTrafficLight/Models.swift \
  Sources/ClaudeTrafficLight/SessionStatusDetector.swift \
  Tests/SessionStatusDetectorTests.swift \
  -o /tmp/ClaudeTrafficLightStatusTests

/tmp/ClaudeTrafficLightStatusTests
node Scripts/claude-status-hook.js --self-test
