# frozen_string_literal: true

# Shared description of MagicForge.xcodeproj, used by generate_xcodeproj.rb (to build it)
# and verify_xcodeproj.rb (to check the generated project still matches).
module MagicForgeProject
  ROOT = File.expand_path('../..', __dir__)
  PROJECT_PATH = File.join(ROOT, 'MagicForge.xcodeproj')

  APP_TARGET = 'MagicForge'
  SCHEME = 'MagicForge'
  BUNDLE_ID = 'com.magicforge.app'
  DEPLOYMENT_TARGET = '14.0'
  # 56 = "Xcode 14.0-compatible" project format. Xcode 15 and 16 open it unchanged and it
  # can carry XCLocalSwiftPackageReference objects.
  OBJECT_VERSION = '56'
  # The .xcodeproj sits next to Package.swift, so the local package is the project directory.
  PACKAGE_RELATIVE_PATH = '.'
  PACKAGE_PRODUCT = 'MFApp'

  MAIN_SWIFT = 'Sources/AppMain/main.swift'
  ASSETS = 'Resources/Assets.xcassets'
  INFO_PLIST = 'Resources/Info.plist'
  ENTITLEMENTS = 'Resources/MagicForge.entitlements'
  VERSION_XCCONFIG = 'Resources/Version.xcconfig'

  PROJECT_SETTINGS = {
    'ALWAYS_SEARCH_USER_PATHS' => 'NO',
    'CLANG_ENABLE_MODULES' => 'YES',
    'CLANG_ENABLE_OBJC_ARC' => 'YES',
    'COPY_PHASE_STRIP' => 'NO',
    'DEAD_CODE_STRIPPING' => 'YES',
    'ENABLE_STRICT_OBJC_MSGSEND' => 'YES',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES',
    'GCC_NO_COMMON_BLOCKS' => 'YES',
    'MACOSX_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
    'SDKROOT' => 'macosx',
    'SWIFT_VERSION' => '5.0'
  }.freeze

  PROJECT_DEBUG = {
    'DEBUG_INFORMATION_FORMAT' => 'dwarf',
    'ENABLE_TESTABILITY' => 'YES',
    'GCC_OPTIMIZATION_LEVEL' => '0',
    'GCC_PREPROCESSOR_DEFINITIONS' => ['DEBUG=1', '$(inherited)'],
    'ONLY_ACTIVE_ARCH' => 'YES',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG $(inherited)',
    'SWIFT_OPTIMIZATION_LEVEL' => '-Onone'
  }.freeze

  PROJECT_RELEASE = {
    'DEBUG_INFORMATION_FORMAT' => 'dwarf-with-dsym',
    'ENABLE_NS_ASSERTIONS' => 'NO',
    # Release builds are universal (arm64 + x86_64).
    'ONLY_ACTIVE_ARCH' => 'NO',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'SWIFT_OPTIMIZATION_LEVEL' => '-O'
  }.freeze

  # Identical for Debug and Release. MARKETING_VERSION / CURRENT_PROJECT_VERSION come from
  # Resources/Version.xcconfig (the target's base configuration).
  TARGET_SETTINGS = {
    'ARCHS' => '$(ARCHS_STANDARD)',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'CODE_SIGN_ENTITLEMENTS' => ENTITLEMENTS,
    # Ad-hoc signature with manual signing: builds on any Mac / CI runner without a team.
    # See docs/RELEASE.md for switching to a Developer ID identity.
    'CODE_SIGN_IDENTITY' => '-',
    'CODE_SIGN_STYLE' => 'Manual',
    'DEVELOPMENT_TEAM' => '',
    'PROVISIONING_PROFILE_SPECIFIER' => '',
    'COMBINE_HIDPI_IMAGES' => 'YES',
    # App Sandbox is OFF on purpose: the sandbox forbids session event taps, synthetic
    # input events, cross-app Accessibility control and loading the private
    # MultitouchSupport.framework, which is everything this app does. The entitlements file
    # therefore has no com.apple.security.app-sandbox key either.
    'ENABLE_APP_SANDBOX' => 'NO',
    'ENABLE_HARDENED_RUNTIME' => 'YES',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'INFOPLIST_FILE' => INFO_PLIST,
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks'],
    'MACOSX_DEPLOYMENT_TARGET' => DEPLOYMENT_TARGET,
    'PRODUCT_BUNDLE_IDENTIFIER' => BUNDLE_ID,
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'SDKROOT' => 'macosx',
    'SWIFT_EMIT_LOC_STRINGS' => 'YES',
    'SWIFT_VERSION' => '5.0'
  }.freeze
end
