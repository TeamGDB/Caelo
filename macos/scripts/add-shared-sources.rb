#!/usr/bin/env ruby
#
# Keeps the shared Swift sources in the Runner target.
#
#   ruby macos/scripts/add-shared-sources.rb
#
# Files under platform/apple are written for both Apple platforms and live
# outside macos/, so Xcode does not find them by itself: each one has to be
# referenced by the project. Adding them by hand means editing project.pbxproj,
# which Xcode rewrites on almost any interaction, so this exists instead.
#
# A list rather than a glob. platform/apple also holds the tunnel extension's
# own sources, which belong to a different target and must not be compiled into
# the app -- a glob would quietly pull them in and produce a binary that links
# the network extension into the host process.
#
# Idempotent: running it twice changes nothing.
require 'xcodeproj'

SOURCES = %w[
  VpnManager.swift
  Updater.swift
].freeze

project_path = File.expand_path('../Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Runner' }
abort 'error: no Runner target' unless target

# Placed beside a file that is already here rather than in a group chosen by
# name. A group's own path is part of how Xcode resolves a relative one, so a
# reference put in the wrong group points at somewhere that does not exist --
# which is exactly what happened when this looked the group up by name.
anchor = project.files.find { |file| file.path == '../platform/apple/VpnManager.swift' }
abort 'error: VpnManager.swift is not in the project; nothing to anchor to' unless anchor
group = anchor.parent

SOURCES.each do |name|
  relative = "../platform/apple/#{name}"

  reference = project.files.find { |file| file.path == relative }
  reference ||= group.new_file(relative).tap do |file|
    file.name = name
    # Copied from the anchor rather than left to default: the default is
    # "<group>", which is right only if the group has no path of its own.
    file.source_tree = anchor.source_tree
  end

  already = target.source_build_phase.files.any? do |build_file|
    build_file.file_ref == reference
  end

  if already
    puts "already there: #{name}"
  else
    target.source_build_phase.add_file_reference(reference)
    puts "added: #{name}"
  end
end

project.save
