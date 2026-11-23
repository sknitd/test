#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates MagicForge.xcodeproj (committed to the repository) with the `xcodeproj` gem.
#
#   gem install xcodeproj
#   ruby Scripts/generate_xcodeproj.rb && ruby Scripts/verify_xcodeproj.rb
#
# Design: one macOS app target, `MagicForge`, whose only compiled source is
# Sources/AppMain/main.swift. All real code lives in the Swift package next to the project
# (Package.swift), referenced as a local package; the app links its `MFApp` library product.
# The package's own executable is called `MagicForgeApp`, so target names do not clash.
# Output is deterministic (predictable object ids), so regenerating produces no diff.

require 'fileutils'
require 'xcodeproj'
require_relative 'lib/project_spec'

include MagicForgeProject # rubocop:disable Style/MixinUsage

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH, false, OBJECT_VERSION.to_i)
project.root_object.attributes['BuildIndependentTargetsInParallel'] = '1'
project.root_object.attributes['LastSwiftUpdateCheck'] = '1600'
project.root_object.attributes['LastUpgradeCheck'] = '1600'
project.root_object.development_region = 'en'
project.root_object.known_regions = %w[en Base]
# Attributes newer gem versions add for Xcode 16 project formats; not part of format 56.
project.root_object.preferred_project_object_version = nil if project.root_object.respond_to?(:preferred_project_object_version=)
if project.root_object.respond_to?(:minimized_project_reference_proxies=)
  project.root_object.minimized_project_reference_proxies = nil
end

# --- Groups and file references (paths relative to the project directory) ---------------
app_group = project.main_group.new_group('App')
main_ref = app_group.new_reference(MAIN_SWIFT)
resources_group = project.main_group.new_group('Resources')
assets_ref = resources_group.new_reference(ASSETS)
resources_group.new_reference(INFO_PLIST)
resources_group.new_reference(ENTITLEMENTS)
xcconfig_ref = resources_group.new_reference(VERSION_XCCONFIG)

# --- App target ------------------------------------------------------------------------
target = project.new_target(:application, APP_TARGET, :osx, DEPLOYMENT_TARGET, nil, :swift)
target.add_file_references([main_ref])
target.add_resources([assets_ref])
# new_target links Cocoa.framework by default; Swift auto-links system frameworks.
target.frameworks_build_phase.files.to_a.each(&:remove_from_project)
project.frameworks_group.recursive_children.reverse_each(&:remove_from_project)
project.frameworks_group.remove_from_project

# --- Build settings ----------------------------------------------------------------------
project.build_configurations.each do |config|
  config.build_settings.clear
  config.build_settings.merge!(PROJECT_SETTINGS)
  config.build_settings.merge!(config.name == 'Debug' ? PROJECT_DEBUG : PROJECT_RELEASE)
end
target.build_configurations.each do |config|
  config.build_settings.clear
  config.build_settings.merge!(TARGET_SETTINGS)
  config.base_configuration_reference = xcconfig_ref
end

# --- Local Swift package + product dependency ----------------------------------------------
package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
package_ref.relative_path = PACKAGE_RELATIVE_PATH
project.root_object.package_references << package_ref

product_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product_dependency.product_name = PACKAGE_PRODUCT
target.package_product_dependencies << product_dependency

link_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
link_file.product_ref = product_dependency
target.frameworks_build_phase.files << link_file

project.predictabilize_uuids
project.sort(groups_position: :above)
project.save

# --- Shared scheme (so `xcodebuild -scheme MagicForge` works on CI) -------------------------
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.launch_action.build_configuration = 'Debug'
scheme.archive_action.build_configuration = 'Release'
scheme.save_as(PROJECT_PATH, SCHEME, true)

puts "Generated #{PROJECT_PATH} (objectVersion #{project.object_version})"
