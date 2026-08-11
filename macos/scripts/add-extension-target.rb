#!/usr/bin/env ruby
#
# Adds the system extension target to macos/Runner.xcodeproj.
#
#   ruby macos/scripts/add-extension-target.rb
#
# A script rather than a committed project file. Xcode rewrites project.pbxproj
# on almost any interaction, so a hand-edited one is a merge conflict waiting to
# happen; this can be read, reviewed and re-run.
#
# Idempotent: running it twice changes nothing.
require 'xcodeproj'

NAME = 'CaeloSystemExtension'
TEAM = 'BM4788UD8M'

# The product is named for the bundle identifier, not for the target.
#
# sysextd matches an extension by executable path, not by the identifier in its
# Info.plist, and refuses any bundle where the two disagree -- reporting it as
# "Extension not found in App bundle", which sends you looking for a missing
# file that is right where it should be. Every shipping network system
# extension is named this way.
IDENTIFIER = 'team.gdb.caelo.SystemExtension'

project = Xcodeproj::Project.open(File.expand_path('../Runner.xcodeproj', __dir__))
app = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'

# Re-running on a project that already has the target rewrites its settings
# rather than bowing out. "Already present" is not the same as "already
# correct", and a project checked in before a setting changed would otherwise
# keep the old one forever, with this script quietly reporting success.
existing = project.targets.find { |t| t.name == NAME }

ext = existing || project.new_target(:system_extension, NAME, :osx, '11.0', nil, :swift)

# The gem does not set these for a system extension, and Xcode refuses to load
# a project whose target has no product type.
ext.product_type = 'com.apple.product-type.system-extension'
ref = ext.product_reference
ref.path = "#{IDENTIFIER}.systemextension"
ref.name = ref.path
ref.explicit_file_type = 'wrapper.system-extension'
ref.include_in_index = '0'
ref.source_tree = 'BUILT_PRODUCTS_DIR'

group = project.main_group[NAME] || project.main_group.new_group(NAME, NAME)
%w[Info.plist CaeloSystemExtension.entitlements]
  .each { |f| group.new_reference(f) unless group.files.any? { |r| r.path == f } }

# The provider is shared with iOS. One implementation, two platforms.
shared = project.main_group.find_subpath('Shared', true)
shared.set_source_tree('SOURCE_ROOT')
%w[PacketTunnelProvider.swift TunnelLog.swift].each do |name|
  path = "../platform/apple/#{name}"
  next if ext.source_build_phase.files_references.any? { |r| r.path == path }

  reference = shared.files.find { |r| r.path == path } || shared.new_reference(path)
  ext.add_file_references([reference])
end

xcconfig = project.main_group.files.find { |f| f.path == 'Flutter/Extension.xcconfig' } ||
           project.main_group.new_reference('Flutter/Extension.xcconfig')

ext.build_configurations.each do |config|
  config.base_configuration_reference = xcconfig
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => IDENTIFIER,
    'PRODUCT_NAME' => IDENTIFIER,
    'WRAPPER_EXTENSION' => 'systemextension',
    'INFOPLIST_FILE' => "#{NAME}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS' => "#{NAME}/#{NAME}.entitlements",
    # Shared with iOS, like the provider it declares for.
    'SWIFT_OBJC_BRIDGING_HEADER' => '../platform/apple/CaeloTunnel-Bridging-Header.h',
    'SWIFT_VERSION' => '5.0',
    'DEVELOPMENT_TEAM' => TEAM,
    # Manual, and Developer ID on every configuration. Automatic signing does
    # not create Developer ID profiles and cannot be made to, and a system
    # extension signed any other way will not load on a machine with SIP on --
    # so there is no configuration where development signing would be useful.
    'CODE_SIGN_STYLE' => 'Manual',
    'CODE_SIGN_IDENTITY' => 'Developer ID Application',
    'PROVISIONING_PROFILE_SPECIFIER' => 'Caelo SystemExtension',
    'MACOSX_DEPLOYMENT_TARGET' => '11.0',
    # From pubspec.yaml, through Flutter's generated xcconfig. See
    # macos/Flutter/Extension.xcconfig for why this cannot be a literal.
    'MARKETING_VERSION' => '$(FLUTTER_BUILD_NAME)',
    'CURRENT_PROJECT_VERSION' => '$(FLUTTER_BUILD_NUMBER)',
    'SKIP_INSTALL' => 'YES',
    # Required for notarisation, and a system extension will not load without
    # having been notarised.
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'OTHER_CODE_SIGN_FLAGS' => '$(inherited) --timestamp',
    'CODE_SIGN_INJECT_BASE_ENTITLEMENTS' => 'NO',
    'HEADER_SEARCH_PATHS' => ['$(inherited)', '$(SRCROOT)/../core/build'],
    # Deliberately not inherited. Flutter puts its plugins' frameworks in the
    # project's link flags, and an extension that inherits them links against
    # frameworks only the app carries: it builds, signs, installs, and then
    # dyld kills it on launch for a missing library. The system reports that
    # as a tunnel that never connects.
    'FRAMEWORK_SEARCH_PATHS' => '',
    # Static, like iOS: a system extension has its own ideas about where
    # libraries live. -force_load because nothing references these symbols at
    # link time, -export_dynamic because keeping them is not the same as being
    # able to find them.
    'OTHER_LDFLAGS' => [
      '-force_load', '$(SRCROOT)/../core/build/libcaelo.a',
      '-Wl,-export_dynamic',
      '-lresolv', '-framework', 'CoreFoundation', '-framework', 'Security',
      '-framework', 'NetworkExtension'
    ]
  )
end

# System extensions live in Contents/Library/SystemExtensions, not PlugIns.
embed = app.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Embed System Extensions' } ||
        app.new_copy_files_build_phase('Embed System Extensions')
# Destination "Wrapper" with a path inside it. 16 is the products directory,
# which is beside the bundle rather than in it — the copy succeeds and lands
# somewhere nothing looks.
embed.symbol_dst_subfolder_spec = :wrapper
embed.dst_path = 'Contents/Library/SystemExtensions'
embed.clear
embed.add_file_reference(ext.product_reference).settings =
  { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.add_dependency(ext) unless app.dependencies.any? { |d| d.target == ext }

# After the frameworks are in place and before Flutter's script rewrites the
# bundle. Not simply "before the first script phase": the first one is the Pods
# manifest check, which runs before anything is compiled, and a copy phase there
# has no bundle to copy into.
after = app.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Bundle Framework' } ||
        app.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
app.build_phases.delete(embed)
app.build_phases.insert((after || app.build_phases.length - 1) + 1, embed)

project.save
puts existing ? "updated #{NAME}" : "added #{NAME}"
