#!/usr/bin/env python3
# Writes FlagcastTV.xcodeproj: Flagcast TV for Apple TV (native SwiftUI, tvOS 17+).
#   python3 tools/make-project.py        (from apps/flagcast-tv-apple)
# FlagcastTV/ is a synchronized group: add Swift files there and Xcode picks them up. Info.plist is generated from the
# INFOPLIST_KEY_ settings below. Each release: change VERSION (and BUILD must go up for App Store Connect).
import hashlib, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def i(name): return hashlib.md5(('flagcast-tv-apple:' + name).encode()).hexdigest()[:24].upper()

TEAM = 'C8KXPB4QNA'
T, PROD, BID, VERSION, BUILD = 'FlagcastTV', 'Flagcast TV', 'app.flagcast.tv', '1.0.0', '1'

def settings():
    return f'''				ASSETCATALOG_COMPILER_APPICON_NAME = "App Icon & Top Shelf Image";
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = {BUILD};
				DEVELOPMENT_TEAM = {TEAM};
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = "{PROD}";
				INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports";
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UIUserInterfaceStyle = Dark;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = {VERSION};
				PRODUCT_BUNDLE_IDENTIFIER = {BID};
				PRODUCT_NAME = "{PROD}";
				SDKROOT = appletvos;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 3;
				TVOS_DEPLOYMENT_TARGET = 17.0;
'''
common = '''				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				SDKROOT = appletvos;
				TVOS_DEPLOYMENT_TARGET = 17.0;
'''
debug = common + '''				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
'''
release = common + '''				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ONLY_ACTIVE_ARCH = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
'''
def cfg(key, name, body):
    return f'''		{i(key)} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{body}			}};
			name = {name};
		}};
'''
def cfglist(key, a, b):
    return f'''		{i(key)} = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{i(a)} /* Debug */,
				{i(b)} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
'''
def phase(key, isa):
    return f'''		{i(key)} = {{
			isa = {isa};
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
'''
P = i('project')
out = f'''// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXFileReference section */
		{i('product')} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{PROD}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{i('group')} = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = {T};
			sourceTree = "<group>";
		}};
/* End PBXFileSystemSynchronizedRootGroup section */

{phase('src', 'PBXSourcesBuildPhase')}{phase('fw', 'PBXFrameworksBuildPhase')}{phase('res', 'PBXResourcesBuildPhase')}
		{i('maingroup')} = {{
			isa = PBXGroup;
			children = (
				{i('group')},
				{i('products')},
			);
			sourceTree = "<group>";
		}};
		{i('products')} = {{
			isa = PBXGroup;
			children = (
				{i('product')},
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{i('target')} = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {i('cfgs')};
			buildPhases = (
				{i('src')},
				{i('fw')},
				{i('res')},
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{i('group')},
			);
			name = {T};
			productName = "{PROD}";
			productReference = {i('product')};
			productType = "com.apple.product-type.application";
		}};
		{P} = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
			}};
			buildConfigurationList = {i('projcfgs')};
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {i('maingroup')};
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = {i('products')};
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{i('target')},
			);
		}};
{cfg('projdebug', 'Debug', debug)}{cfg('projrelease', 'Release', release)}{cfg('debug', 'Debug', settings())}{cfg('release', 'Release', settings())}{cfglist('projcfgs', 'projdebug', 'projrelease')}{cfglist('cfgs', 'debug', 'release')}	}};
	rootObject = {P};
}}
'''
proj = os.path.join(ROOT, 'FlagcastTV.xcodeproj')
os.makedirs(os.path.join(proj, 'xcshareddata', 'xcschemes'), exist_ok=True)
open(os.path.join(proj, 'project.pbxproj'), 'w').write(out)
ref = f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{i("target")}" BuildableName = "{PROD}.app" BlueprintName = "{T}" ReferencedContainer = "container:FlagcastTV.xcodeproj"></BuildableReference>'
open(os.path.join(proj, 'xcshareddata', 'xcschemes', f'{T}.xcscheme'), 'w').write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2700" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref}
      </BuildableProductRunnable>
      <CommandLineArguments>
         <CommandLineArgument argument = "-FlagcastServer http://localhost:8787" isEnabled = "NO">
         </CommandLineArgument>
      </CommandLineArguments>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''')
print('wrote', proj)
