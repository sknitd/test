#!/usr/bin/env ruby
# frozen_string_literal: true

# Re-opens MagicForge.xcodeproj with the `xcodeproj` gem and checks that it still has the
# expected target, build settings, file references, local package reference and shared
# scheme. Exits non-zero listing every mismatch.
#
#   ruby Scripts/verify_xcodeproj.rb

require 'rexml/document'
require 'xcodeproj'
require_relative 'lib/project_spec'

include MagicForgeProject # rubocop:disable Style/MixinUsage

failures = []
check = lambda do |description, condition|
  puts "#{condition ? 'ok  ' : 'FAIL'} #{description}"
  failures << description unless condition
end

project = Xcodeproj::Project.open(PROJECT_PATH)
check.call("objectVersion is #{OBJECT_VERSION}", project.object_version == OBJECT_VERSION)
check.call('exactly one target', project.targets.size == 1)

target = project.targets.find { |t| t.name == APP_TARGET }
check.call("target #{APP_TARGET} exists", !target.nil?)
abort("\nNo #{APP_TARGET} target; cannot continue.") if target.nil?

check.call('target is a macOS application',
           target.product_type == 'com.apple.product-type.application' && target.platform_name == :osx)
check.call('product is MagicForge.app', target.product_reference&.path == 'MagicForge.app')

sources = target.source_build_phase.files.map { |f| f.file_ref&.path }
check.call("only compiled source is #{MAIN_SWIFT}", sources == [MAIN_SWIFT])
resources = target.resources_build_phase.files.map { |f| f.file_ref&.path }
check.call("resources are [#{ASSETS}]", resources == [ASSETS])

project.files.each do |file|
  next if file.source_tree == 'BUILT_PRODUCTS_DIR'

  path = File.join(ROOT, file.path.to_s)
  # main.swift belongs to another agent and may not be written yet; warn instead of failing.
  if file.path == MAIN_SWIFT && !File.exist?(path)
    puts "warn #{MAIN_SWIFT} does not exist yet"
    next
  end
  check.call("referenced file exists: #{file.path}", File.exist?(path))
end

check.call('Debug and Release configurations',
           target.build_configurations.map(&:name).sort == %w[Debug Release])
target.build_configurations.each do |config|
  TARGET_SETTINGS.each do |key, expected|
    check.call("#{config.name}: #{key} = #{expected.inspect}", config.build_settings[key] == expected)
  end
  check.call("#{config.name}: base configuration is #{VERSION_XCCONFIG}",
             config.base_configuration_reference&.path == VERSION_XCCONFIG)
  check.call("#{config.name}: no CODE_SIGN_IDENTITY override that needs a team",
             config.build_settings.keys.none? { |k| k.start_with?('CODE_SIGN_IDENTITY[') })
end
project.build_configurations.each do |config|
  expected = PROJECT_SETTINGS.merge(config.name == 'Debug' ? PROJECT_DEBUG : PROJECT_RELEASE)
  expected.each do |key, value|
    check.call("project #{config.name}: #{key} = #{value.inspect}", config.build_settings[key] == value)
  end
end

packages = project.root_object.package_references
check.call('one local Swift package reference',
           packages.size == 1 && packages.first.is_a?(Xcodeproj::Project::Object::XCLocalSwiftPackageReference))
check.call("package relativePath is #{PACKAGE_RELATIVE_PATH.inspect}",
           packages.first&.relative_path == PACKAGE_RELATIVE_PATH)
check.call('Package.swift exists at that path',
           File.exist?(File.join(ROOT, PACKAGE_RELATIVE_PATH, 'Package.swift')))

deps = target.package_product_dependencies
check.call("target depends on package product #{PACKAGE_PRODUCT}",
           deps.map(&:product_name) == [PACKAGE_PRODUCT])
linked = target.frameworks_build_phase.files.map { |f| f.product_ref&.product_name }
check.call("#{PACKAGE_PRODUCT} is in the Frameworks build phase", linked == [PACKAGE_PRODUCT])

manifest = File.read(File.join(ROOT, 'Package.swift'))
check.call("Package.swift declares library product #{PACKAGE_PRODUCT}",
           manifest.match?(/\.library\(name:\s*"#{PACKAGE_PRODUCT}"/))
check.call("no package target is named #{APP_TARGET}",
           !manifest.match?(/[Tt]arget\(\s*name:\s*"#{APP_TARGET}"/))

scheme_path = File.join(PROJECT_PATH, 'xcshareddata', 'xcschemes', "#{SCHEME}.xcscheme")
check.call("shared scheme #{SCHEME} exists", File.exist?(scheme_path))
if File.exist?(scheme_path)
  doc = REXML::Document.new(File.read(scheme_path))
  refs = REXML::XPath.match(doc, '//BuildableReference')
  check.call('scheme builds and launches MagicForge.app',
             refs.size >= 2 && refs.all? do |ref|
               ref.attributes['BlueprintName'] == APP_TARGET &&
                 ref.attributes['BuildableName'] == 'MagicForge.app' &&
                 ref.attributes['BlueprintIdentifier'] == target.uuid &&
                 ref.attributes['ReferencedContainer'] == 'container:MagicForge.xcodeproj'
             end)
end

pbxproj = File.read(File.join(PROJECT_PATH, 'project.pbxproj'))
check.call('pbxproj starts with the UTF-8 marker', pbxproj.start_with?('// !$*UTF8*$!'))
check.call('pbxproj braces are balanced', pbxproj.count('{') == pbxproj.count('}'))

if failures.empty?
  puts "\nMagicForge.xcodeproj verified."
else
  puts "\n#{failures.size} check(s) failed."
  exit 1
end
