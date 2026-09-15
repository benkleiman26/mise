#!/usr/bin/env python3
"""Writes Mise.xcodeproj/project.pbxproj.

Hand writing this format is error prone and there is no Xcode here to open the
result, so it is generated from a description and then checked by
validate_pbxproj.py, which resolves every object reference.
"""
import pathlib, sys

def oid(n: int) -> str:
    s = f"{n:X}"
    return ("AB1E" + "0" * (24 - 4 - len(s)) + s)

ID = {}
for i, key in enumerate([
    "project", "mainGroup", "productsGroup",
    "syncMise", "syncTests",
    "appTarget", "testTarget",
    "appProduct", "testProduct",
    "appSources", "appFrameworks", "appResources",
    "testSources", "testFrameworks", "testResources",
    "testDependency", "testProxy",
    "projectConfigList", "appConfigList", "testConfigList",
    "projectDebug", "projectRelease",
    "appDebug", "appRelease",
    "testDebug", "testRelease",
], start=1):
    ID[key] = oid(i)
assert len({*ID.values()}) == len(ID)
assert all(len(v) == 24 for v in ID.values())

PROJECT_COMMON = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOL_EXTENSIONS": "YES",
    "ASSETCATALOG_COMPILER_GENERATE_ASSET_SYMBOL_FRAMEWORKS": "SwiftUI",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_ENABLE_OBJC_WEAK": "YES",
    "CLANG_WARN_BOOL_CONVERSION": "YES",
    "CLANG_WARN_CONSTANT_CONVERSION": "YES",
    "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
    "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
    "CLANG_WARN_EMPTY_BODY": "YES",
    "CLANG_WARN_ENUM_CONVERSION": "YES",
    "CLANG_WARN_INFINITE_RECURSION": "YES",
    "CLANG_WARN_INT_CONVERSION": "YES",
    "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
    "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
    "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
    "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
    "CLANG_WARN_STRICT_PROTOTYPES": "YES",
    "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
    "CLANG_WARN_UNREACHABLE_CODE": "YES",
    "CLANG_WARN__DUPLICATE_METHOD_MATCH": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
    "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
    "GCC_WARN_UNDECLARED_SELECTOR": "YES",
    "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
    "GCC_WARN_UNUSED_FUNCTION": "YES",
    "GCC_WARN_UNUSED_VARIABLE": "YES",
    # Section 3 of the spec and DECISIONS.md: iOS 18, not the 17 written when
    # 17 was one version back.
    "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "MTL_FAST_MATH": "YES",
    "SDKROOT": "iphoneos",
    # Phase 0b is a skeleton and Swift 5 mode keeps it that way. Revisit when
    # the services that actually do concurrent work arrive.
    "SWIFT_STRICT_CONCURRENCY": "minimal",
}

PROJECT_DEBUG = {
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": ("DEBUG=1", "$(inherited)"),
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}

PROJECT_RELEASE = {
    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS": "NO",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
}

APP_COMMON = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Mise",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
    "LD_RUNPATH_SEARCH_PATHS": ("$(inherited)", "@executable_path/Frameworks"),
    "MARKETING_VERSION": "0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.benkleiman.mise",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
}

TEST_COMMON = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "MARKETING_VERSION": "0.1",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.benkleiman.mise.tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Mise.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Mise",
}

NEEDS_QUOTES = set(' "\'()${}<>,=;:@&#+*?[]!%^|\\/~`')

def quoted(value: str) -> str:
    if value == "":
        return '""'
    if any(c in NEEDS_QUOTES for c in value):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return value

def settings_block(settings: dict, indent: str) -> str:
    lines = []
    for key in sorted(settings):
        value = settings[key]
        if isinstance(value, tuple):
            lines.append(f"{indent}{key} = (")
            for element in value:
                lines.append(f"{indent}\t{quoted(element)},")
            lines.append(f"{indent});")
        else:
            lines.append(f"{indent}{key} = {quoted(value)};")
    return "\n".join(lines)

def build_configuration(config_id, name, settings, comment):
    return f"""\t\t{config_id} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
{settings_block(settings, chr(9) * 4)}
\t\t\t}};
\t\t\tname = {name};
\t\t}};"""

project_debug = dict(PROJECT_COMMON); project_debug.update(PROJECT_DEBUG)
project_release = dict(PROJECT_COMMON); project_release.update(PROJECT_RELEASE)

text = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 77;
\tobjects = {{

/* Begin PBXFileReference section */
\t\t{ID['appProduct']} /* Mise.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Mise.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{ID['testProduct']} /* MiseTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MiseTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
\t\t{ID['syncMise']} /* Mise */ = {{
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\tpath = Mise;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ID['syncTests']} /* MiseTests */ = {{
\t\t\tisa = PBXFileSystemSynchronizedRootGroup;
\t\t\tpath = MiseTests;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{ID['appFrameworks']} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{ID['testFrameworks']} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{ID['mainGroup']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ID['syncMise']} /* Mise */,
\t\t\t\t{ID['syncTests']} /* MiseTests */,
\t\t\t\t{ID['productsGroup']} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{ID['productsGroup']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ID['appProduct']} /* Mise.app */,
\t\t\t\t{ID['testProduct']} /* MiseTests.xctest */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{ID['appTarget']} /* Mise */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ID['appConfigList']} /* Build configuration list for PBXNativeTarget "Mise" */;
\t\t\tbuildPhases = (
\t\t\t\t{ID['appSources']} /* Sources */,
\t\t\t\t{ID['appFrameworks']} /* Frameworks */,
\t\t\t\t{ID['appResources']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{ID['syncMise']} /* Mise */,
\t\t\t);
\t\t\tname = Mise;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = Mise;
\t\t\tproductReference = {ID['appProduct']} /* Mise.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{ID['testTarget']} /* MiseTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ID['testConfigList']} /* Build configuration list for PBXNativeTarget "MiseTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{ID['testSources']} /* Sources */,
\t\t\t\t{ID['testFrameworks']} /* Frameworks */,
\t\t\t\t{ID['testResources']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t{ID['testDependency']} /* PBXTargetDependency */,
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{ID['syncTests']} /* MiseTests */,
\t\t\t);
\t\t\tname = MiseTests;
\t\t\tpackageProductDependencies = (
\t\t\t);
\t\t\tproductName = MiseTests;
\t\t\tproductReference = {ID['testProduct']} /* MiseTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{ID['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 2700;
\t\t\t\tLastUpgradeCheck = 2700;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t{ID['appTarget']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;
\t\t\t\t\t}};
\t\t\t\t\t{ID['testTarget']} = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;
\t\t\t\t\t\tTestTargetID = {ID['appTarget']};
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = {ID['projectConfigList']} /* Build configuration list for PBXProject "Mise" */;
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {ID['mainGroup']};
\t\t\tminimizedProjectReferenceProxies = 1;
\t\t\tpreferredProjectObjectVersion = 77;
\t\t\tproductRefGroup = {ID['productsGroup']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{ID['appTarget']} /* Mise */,
\t\t\t\t{ID['testTarget']} /* MiseTests */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{ID['appResources']} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{ID['testResources']} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{ID['appSources']} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{ID['testSources']} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t{ID['testDependency']} /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = {ID['appTarget']} /* Mise */;
\t\t\ttargetProxy = {ID['testProxy']} /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin PBXContainerItemProxy section */
\t\t{ID['testProxy']} /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = {ID['project']} /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = {ID['appTarget']};
\t\t\tremoteInfo = Mise;
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin XCBuildConfiguration section */
{build_configuration(ID['projectDebug'], 'Debug', project_debug, 'Debug')}
{build_configuration(ID['projectRelease'], 'Release', project_release, 'Release')}
{build_configuration(ID['appDebug'], 'Debug', APP_COMMON, 'Debug')}
{build_configuration(ID['appRelease'], 'Release', APP_COMMON, 'Release')}
{build_configuration(ID['testDebug'], 'Debug', TEST_COMMON, 'Debug')}
{build_configuration(ID['testRelease'], 'Release', TEST_COMMON, 'Release')}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{ID['projectConfigList']} /* Build configuration list for PBXProject "Mise" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ID['projectDebug']} /* Debug */,
\t\t\t\t{ID['projectRelease']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ID['appConfigList']} /* Build configuration list for PBXNativeTarget "Mise" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ID['appDebug']} /* Debug */,
\t\t\t\t{ID['appRelease']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ID['testConfigList']} /* Build configuration list for PBXNativeTarget "MiseTests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ID['testDebug']} /* Debug */,
\t\t\t\t{ID['testRelease']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = {ID['project']} /* Project object */;
}}
"""

out = pathlib.Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(text)
print(f"wrote {out} ({len(text)} bytes, {len(ID)} objects)")
