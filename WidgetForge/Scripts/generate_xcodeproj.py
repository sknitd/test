#!/usr/bin/env python3
"""Generates WidgetForge.xcodeproj.

The project uses Xcode 16 file-system-synchronised groups: every Swift file inside a listed folder is built
automatically, so adding a source file never requires editing the project. Re-run this script only when the
folder layout, targets or build settings change. Output is deterministic (stable object ids)."""
import hashlib, os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

def oid(name):
    return hashlib.md5(("widgetforge:" + name).encode()).hexdigest()[:24].upper()

# Folders compiled into both the app and the widget extension (no AppKit-app-only code).
SHARED = ["Core", "Persistence", "DataSources", "Security", "Scripting", "Automation", "Profiles", "Diagnostics", "Widgets"]
APP_ONLY = ["App", "Desktop", "UI", "Builder"]

def q(v):
    v = str(v)
    safe = v and all(c.isalnum() or c in "._/" for c in v)
    return v if safe else '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'

def settings(d, indent="\t\t\t\t"):
    lines = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            lines.append(f"{indent}{k} = (\n" + "".join(f"{indent}\t{q(x)},\n" for x in v) + f"{indent});")
        else:
            lines.append(f"{indent}{k} = {q(v)};")
    return "\n".join(lines)

COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "CODE_SIGN_STYLE": "Automatic", "CODE_SIGN_IDENTITY": "-", "DEVELOPMENT_TEAM": "",
    "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0", "DEAD_CODE_STRIPPING": "YES",
    "ENABLE_HARDENED_RUNTIME": "YES", "MACOSX_DEPLOYMENT_TARGET": "14.0", "SDKROOT": "macosx",
    "SWIFT_VERSION": "5.0", "GCC_NO_COMMON_BLOCKS": "YES", "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES", "SWIFT_EMIT_LOC_STRINGS": "NO",
    # On macOS an App Group id embeds the signing team, so it is derived here and read back from Info.plist.
    "WF_APP_GROUP": "$(TeamIdentifierPrefix)com.widgetforge.shared",
}
DEBUG = dict(COMMON, DEBUG_INFORMATION_FORMAT="dwarf", ENABLE_TESTABILITY="YES", GCC_OPTIMIZATION_LEVEL="0",
             ONLY_ACTIVE_ARCH="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG $(inherited)", SWIFT_OPTIMIZATION_LEVEL="-Onone")
RELEASE = dict(COMMON, DEBUG_INFORMATION_FORMAT="dwarf-with-dsym", ENABLE_NS_ASSERTIONS="NO", SWIFT_COMPILATION_MODE="wholemodule",
               SWIFT_OPTIMIZATION_LEVEL="-O")
APP = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/WidgetForge.entitlements", "COMBINE_HIDPI_IMAGES": "YES",
    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": "Config/App-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "WidgetForge",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.utilities",
    "INFOPLIST_KEY_NSHumanReadableCopyright": "",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "com.widgetforge.app", "PRODUCT_NAME": "$(TARGET_NAME)",
}
EXT = {
    "APPLICATION_EXTENSION_API_ONLY": "YES", "CODE_SIGN_ENTITLEMENTS": "Config/WidgetForgeWidgets.entitlements",
    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_FILE": "Config/Widgets-Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "WidgetForge", "INFOPLIST_KEY_NSHumanReadableCopyright": "",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@executable_path/../../../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": "com.widgetforge.app.widgets", "PRODUCT_NAME": "$(TARGET_NAME)", "SKIP_INSTALL": "YES",
}

P = oid("project")
MAIN, PRODUCTS, SOURCES = oid("group.main"), oid("group.products"), oid("group.sources")
APP_T, EXT_T = oid("target.app"), oid("target.ext")
APP_REF, EXT_REF = oid("product.app"), oid("product.ext")
sync = {name: oid("sync." + name) for name in SHARED + APP_ONLY}
SYNC_RES, SYNC_EXT = oid("sync.Resources"), oid("sync.WidgetExtension")
EMBED_FILE, EMBED_PHASE = oid("embed.file"), oid("embed.phase")
PROXY, DEP = oid("proxy"), oid("dependency")
phase = {t: {p: oid(f"phase.{t}.{p}") for p in ("Sources", "Frameworks", "Resources")} for t in ("app", "ext")}
cfg = {f"{scope}.{name}": oid(f"config.{scope}.{name}") for scope in ("project", "app", "ext") for name in ("Debug", "Release")}
lists = {scope: oid("configlist." + scope) for scope in ("project", "app", "ext")}

o = []
o.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n")

o.append("\n/* Begin PBXBuildFile section */\n")
o.append(f"\t\t{EMBED_FILE} /* WidgetForgeWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {EXT_REF} /* WidgetForgeWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
o.append("/* End PBXBuildFile section */\n")

o.append("\n/* Begin PBXContainerItemProxy section */\n")
o.append(f"\t\t{PROXY} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {P} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {EXT_T};\n\t\t\tremoteInfo = WidgetForgeWidgets;\n\t\t}};\n")
o.append("/* End PBXContainerItemProxy section */\n")

o.append("\n/* Begin PBXCopyFilesBuildPhase section */\n")
o.append(f"\t\t{EMBED_PHASE} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\t{EMBED_FILE} /* WidgetForgeWidgets.appex in Embed Foundation Extensions */,\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXCopyFilesBuildPhase section */\n")

o.append("\n/* Begin PBXFileReference section */\n")
o.append(f"\t\t{APP_REF} /* WidgetForge.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = WidgetForge.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
o.append(f"\t\t{EXT_REF} /* WidgetForgeWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = WidgetForgeWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
o.append("/* End PBXFileReference section */\n")

o.append("\n/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
for name in sorted(sync):
    o.append(f"\t\t{sync[name]} /* {name} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = {name};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append(f"\t\t{SYNC_RES} /* Resources */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = Resources;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append(f"\t\t{SYNC_EXT} /* WidgetExtension */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = WidgetExtension;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append("/* End PBXFileSystemSynchronizedRootGroup section */\n")

o.append("\n/* Begin PBXFrameworksBuildPhase section */\n")
for t in ("app", "ext"):
    o.append(f"\t\t{phase[t]['Frameworks']} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXFrameworksBuildPhase section */\n")

o.append("\n/* Begin PBXGroup section */\n")
o.append(f"\t\t{MAIN} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{SOURCES} /* Sources */,\n\t\t\t\t{SYNC_EXT} /* WidgetExtension */,\n\t\t\t\t{SYNC_RES} /* Resources */,\n\t\t\t\t{PRODUCTS} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append(f"\t\t{SOURCES} /* Sources */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + "".join(f"\t\t\t\t{sync[n]} /* {n} */,\n" for n in APP_ONLY + SHARED) + f"\t\t\t);\n\t\t\tpath = Sources;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append(f"\t\t{PRODUCTS} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{APP_REF} /* WidgetForge.app */,\n\t\t\t\t{EXT_REF} /* WidgetForgeWidgets.appex */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
o.append("/* End PBXGroup section */\n")

def target(tid, name, key, product_ref, product_file, product_type, groups, extra_phases="", deps=""):
    g = "".join(f"\t\t\t\t{gid} /* {gname} */,\n" for gname, gid in groups)
    return (f"\t\t{tid} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {lists[key]} /* Build configuration list for PBXNativeTarget \"{name}\" */;\n"
            f"\t\t\tbuildPhases = (\n\t\t\t\t{phase[key]['Sources']} /* Sources */,\n\t\t\t\t{phase[key]['Frameworks']} /* Frameworks */,\n\t\t\t\t{phase[key]['Resources']} /* Resources */,\n{extra_phases}\t\t\t);\n"
            f"\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n{deps}\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n{g}\t\t\t);\n"
            f"\t\t\tname = {name};\n\t\t\tpackageProductDependencies = (\n\t\t\t);\n\t\t\tproductName = {name};\n\t\t\tproductReference = {product_ref} /* {product_file} */;\n\t\t\tproductType = \"{product_type}\";\n\t\t}};\n")

o.append("\n/* Begin PBXNativeTarget section */\n")
o.append(target(APP_T, "WidgetForge", "app", APP_REF, "WidgetForge.app", "com.apple.product-type.application",
                [(n, sync[n]) for n in APP_ONLY + SHARED] + [("Resources", SYNC_RES)],
                extra_phases=f"\t\t\t\t{EMBED_PHASE} /* Embed Foundation Extensions */,\n", deps=f"\t\t\t\t{DEP} /* PBXTargetDependency */,\n"))
o.append(target(EXT_T, "WidgetForgeWidgets", "ext", EXT_REF, "WidgetForgeWidgets.appex", "com.apple.product-type.app-extension",
                [(n, sync[n]) for n in SHARED] + [("WidgetExtension", SYNC_EXT)]))
o.append("/* End PBXNativeTarget section */\n")

o.append("\n/* Begin PBXProject section */\n")
o.append(f"\t\t{P} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t\tTargetAttributes = {{\n\t\t\t\t\t{APP_T} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n\t\t\t\t\t{EXT_T} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t}};\n\t\t\t\t}};\n\t\t\t}};\n"
         f"\t\t\tbuildConfigurationList = {lists['project']} /* Build configuration list for PBXProject \"WidgetForge\" */;\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n"
         f"\t\t\tmainGroup = {MAIN};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {PRODUCTS} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n\t\t\t\t{APP_T} /* WidgetForge */,\n\t\t\t\t{EXT_T} /* WidgetForgeWidgets */,\n\t\t\t);\n\t\t}};\n")
o.append("/* End PBXProject section */\n")

o.append("\n/* Begin PBXResourcesBuildPhase section */\n")
for t in ("app", "ext"):
    o.append(f"\t\t{phase[t]['Resources']} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXResourcesBuildPhase section */\n")

o.append("\n/* Begin PBXSourcesBuildPhase section */\n")
for t in ("app", "ext"):
    o.append(f"\t\t{phase[t]['Sources']} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
o.append("/* End PBXSourcesBuildPhase section */\n")

o.append("\n/* Begin PBXTargetDependency section */\n")
o.append(f"\t\t{DEP} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {EXT_T} /* WidgetForgeWidgets */;\n\t\t\ttargetProxy = {PROXY} /* PBXContainerItemProxy */;\n\t\t}};\n")
o.append("/* End PBXTargetDependency section */\n")

o.append("\n/* Begin XCBuildConfiguration section */\n")
for key, name, values in (("project.Debug", "Debug", DEBUG), ("project.Release", "Release", RELEASE), ("app.Debug", "Debug", APP), ("app.Release", "Release", APP),
                          ("ext.Debug", "Debug", EXT), ("ext.Release", "Release", EXT)):
    o.append(f"\t\t{cfg[key]} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(values)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};\n")
o.append("/* End XCBuildConfiguration section */\n")

o.append("\n/* Begin XCConfigurationList section */\n")
for scope, label in (("project", 'PBXProject "WidgetForge"'), ("app", 'PBXNativeTarget "WidgetForge"'), ("ext", 'PBXNativeTarget "WidgetForgeWidgets"')):
    o.append(f"\t\t{lists[scope]} /* Build configuration list for {label} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{cfg[scope + '.Debug']} /* Debug */,\n\t\t\t\t{cfg[scope + '.Release']} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
o.append("/* End XCConfigurationList section */\n")

o.append(f"\t}};\n\trootObject = {P} /* Project object */;\n}}\n")

proj = os.path.join(ROOT, "WidgetForge.xcodeproj")
os.makedirs(os.path.join(proj, "project.xcworkspace"), exist_ok=True)
with open(os.path.join(proj, "project.pbxproj"), "w") as f:
    f.write("".join(o))
with open(os.path.join(proj, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
    f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
print("wrote", os.path.relpath(proj, ROOT))
