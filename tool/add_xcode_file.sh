#!/usr/bin/env bash
# Register a source file with an Xcode target without opening Xcode.
#
#   tool/add_xcode_file.sh Runner/Notch/MouseGate.swift Runner
#   tool/add_xcode_file.sh RunnerTests/MouseGateTests.swift RunnerTests
#
# Path is relative to macos/. Idempotent: re-running is a no-op.
set -euo pipefail

REL="${1:?usage: add_xcode_file.sh <path-relative-to-macos> [target]}"
TARGET="${2:-Runner}"

if [ ! -f "macos/$REL" ]; then
  echo "macos/$REL does not exist — create the file first" >&2
  exit 1
fi

ruby -r xcodeproj -e '
  rel, target_name = ARGV
  project = Xcodeproj::Project.open("macos/Runner.xcodeproj")
  target = project.targets.find { |t| t.name == target_name }
  abort "no target named #{target_name}" if target.nil?

  group = project.main_group
  File.dirname(rel).split("/").each do |segment|
    group = group[segment] || group.new_group(segment, segment)
  end

  name = File.basename(rel)
  ref = group.files.find { |f| f.path == name } || group.new_reference(name)
  target.add_file_references([ref]) unless target.source_build_phase.files_references.include?(ref)

  project.save
  puts "registered #{rel} with #{target_name}"
' "$REL" "$TARGET"
