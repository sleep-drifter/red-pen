#!/bin/sh
# Xcode Cloud post-clone hook: the .xcodeproj is generated, not committed,
# so recreate it before Xcode Cloud resolves and builds the project.
set -e

brew install xcodegen

cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
