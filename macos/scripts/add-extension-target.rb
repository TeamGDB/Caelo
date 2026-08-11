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

project = Xcodeproj::Project.open(File.expand_path('../Runner.xcodeproj', __dir__))
app = project.targets.find { |t| t.name == 'Runner' } or abort 'no Runner target'

if project.targets.any? { |t| t.name == NAME }
  puts "#{NAME} already present"
  exit 0
end

ext = project.new_target(:system_extension, NAME, :osx, '11.0', nil, :swift)

# The gem does not set these for a system extension, and Xcode refuses to load
# a project whose target has no product type.
ext.product_type = 'com.apple.product-type.system-extension'
ref = ext.product_reference
ref.path = "#{NAME}.systemextension"
ref.name = ref.path
ref.explicit_file_type = 'wrapper.system-extension'
ref.include_in_index = '0'
ref.source_tree = 'BUILT_PRODUCTS_DIR'

group = project.main_group.new_group(NAME, NAME)
%w[Info.plist CaeloSystemExtension.entitlements CaeloSystemExtension-Bridging-Header.h]
  .each { |f| group.new_reference(f) }

# The provider is shared with iOS. One implementation, two platforms.
shared = project.main_group.find_subpath('Shared', true)
shared.set_source_tree('SOURCE_ROOT')
%w[PacketTunnelProvider.swift TunnelLog.swift].each do |name|
  ext.add_file_references([shared.new_reference("../platform/apple/#{name}")])
end

ext.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'team.gdb.caelo.SystemExtension',
    'PRODUCT_NAME' => NAME,
    'WRAPPER_EXTENSION' => 'systemextension',
    'INFOPLIST_FILE' => "#{NAME}/Info.plist",
    'CODE_SIGN_ENTITLEMENTS' => "#{NAME}/#{NAME}.entitlements",
    'SWIFT_OBJC_BRIDGING_HEADER' => "#{NAME}/#{NAME}-Bridging-Header.h",
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
    'MARKETING_VERSION' => '0.1.0',
    'CURRENT_PROJECT_VERSION' => '1',
    'SKIP_INSTALL' => 'YES',
    # Required for notarisation, and a system extension will not load without
    # having been notarised.
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'OTHER_CODE_SIGN_FLAGS' => '$(inherited) --timestamp',
    'CODE_SIGN_INJECT_BASE_ENTITLEMENTS' => 'NO',
    'HEADER_SEARCH_PATHS' => ['$(inherited)', '$(SRCROOT)/../core/build'],
    # Static, like iOS: a system extension has its own ideas about where
    # libraries live. -force_load because nothing references these symbols at
    # link time, -export_dynamic because keeping them is not the same as being
    # able to find them.
    'OTHER_LDFLAGS' => [
      '$(inherited)',
      '-force_load', '$(SRCROOT)/../core/build/libcaelo.a',
      '-Wl,-export_dynamic',
      '-lresolv', '-framework', 'CoreFoundation', '-framework', 'Security',
      '-framework', 'NetworkExtension'
    ]
  )
end

# System extensions live in Contents/Library/SystemExtensions, not PlugIns.
embed = app.new_copy_files_build_phase('Embed System Extensions')
# Destination "Wrapper" with a path inside it. 16 is the products directory,
# which is beside the bundle rather than in it — the copy succeeds and lands
# somewhere nothing looks.
embed.symbol_dst_subfolder_spec = :wrapper
embed.dst_path = 'Contents/Library/SystemExtensions'
embed.add_file_reference(ext.product_reference).settings =
  { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.add_dependency(ext)

# After the frameworks are in place and before Flutter's script rewrites the
# bundle. Not simply "before the first script phase": the first one is the Pods
# manifest check, which runs before anything is compiled, and a copy phase there
# has no bundle to copy into.
after = app.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Bundle Framework' } ||
        app.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXResourcesBuildPhase) }
app.build_phases.delete(embed)
app.build_phases.insert((after || app.build_phases.length - 1) + 1, embed)

project.save
puts "added #{NAME}"
