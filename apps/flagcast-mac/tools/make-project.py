#!/usr/bin/env python3
# Writes FlagcastMac.xcodeproj: the native Mac apps Flagcast Manager and Flagcast Admin (SwiftUI, macOS 15+).
#   python3 tools/make-project.py        (from apps/flagcast-mac)
# Folders Shared/, Manager/ and Admin/ are synchronized groups: add Swift files there and Xcode picks them up.
# The iPhone app's tournament model, scoring math, server calls and live feed are shared by reference (SHARED_IOS).
# Sparkle (one-click updates) is Vendor/Sparkle.xcframework, fetched and checked by tools/get-sparkle.sh.
import hashlib, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def i(name): return hashlib.md5(('flagcast-mac:' + name).encode()).hexdigest()[:24].upper()

TEAM = 'C8KXPB4QNA'
# (target, product name, bundle id, version, extra source folders)
TARGETS = [
    ('Manager', 'Flagcast Manager', 'app.flagcast.manager', '2.9.13'),
    ('Admin', 'Flagcast Admin', 'app.flagcast.admin', '2.2.0'),
]
# the build number (CFBundleVersion): raise it by one for every Manager release. Sparkle offers an update only when the
# feed's build is higher than the installed one (the version alone isn't enough); tools/release.sh checks this.
BUILDS = {'Manager': '16', 'Admin': '1'}
# Admin is retired (folded into Manager): its last version is only Admin/RetiredApp.swift, no shared code or updater
FULL = {'Manager'}
SHARED_IOS = ['Model/Models.swift', 'Model/Core.swift', 'Model/FlyPath.swift', 'Net/Server.swift', 'Net/EventFeed.swift']

def settings(t, prod, bid, ver):
    # Manager: load the NDI runtime installed on the Mac (NDI cameras). No Sign in with Apple on the Mac: it needs a
    # Developer ID provisioning profile made by hand in the developer account.
    ent = '				CODE_SIGN_ENTITLEMENTS = Manager.entitlements;\n' if t == 'Manager' else ''
    return f'''				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
{ent}				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = {BUILDS[t]};
				DEVELOPMENT_TEAM = {TEAM};
				ENABLE_HARDENED_RUNTIME = YES;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_FILE = "{t}/Info.plist";
				INFOPLIST_KEY_CFBundleDisplayName = "{prod}";
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.sports";
				INFOPLIST_KEY_NSHumanReadableCopyright = "Flagcast";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				MARKETING_VERSION = {ver};
				PRODUCT_BUNDLE_IDENTIFIER = {bid};
				PRODUCT_NAME = "{prod}";
				SDKROOT = macosx;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
'''
common = '''				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				MACOSX_DEPLOYMENT_TARGET = 15.0;
				SDKROOT = macosx;
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

P = i('project')
files = ''.join(f'''		{i(t+'product')} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{prod}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
''' for t, prod, _, _ in TARGETS)
files += ''.join(f'''		{i('ios'+f)} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {os.path.basename(f)}; path = "../flagcast-ios/Flagcast/{f}"; sourceTree = SOURCE_ROOT; }};
''' for f in SHARED_IOS)
buildfiles = ''.join(f'''		{i(t+'bf'+f)} = {{isa = PBXBuildFile; fileRef = {i('ios'+f)}; }};
''' for t, _, _, _ in TARGETS if t in FULL for f in SHARED_IOS)
files += f'''		{i('sparklefw')} = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; path = Vendor/Sparkle.xcframework; sourceTree = "<group>"; }};
'''
buildfiles += ''.join(f'''		{i(t+'bfsparkle')} = {{isa = PBXBuildFile; fileRef = {i('sparklefw')}; }};
		{i(t+'bfsparkleembed')} = {{isa = PBXBuildFile; fileRef = {i('sparklefw')}; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }}; }};
''' for t, _, _, _ in TARGETS if t in FULL)
# Info.plist sits in each folder but is used through INFOPLIST_FILE, not copied as a resource
exceptions = ''.join(f'''		{i(t+'exc')} = {{
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = {i(t+'target')};
		}};
''' for t, _, _, _ in TARGETS)
groups = f'''		{i('Sharedgroup')} = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Shared;
			sourceTree = "<group>";
		}};
''' + ''.join(f'''		{i(t+'group')} = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				{i(t+'exc')},
			);
			path = {t};
			sourceTree = "<group>";
		}};
''' for t, _, _, _ in TARGETS)
def phase(key, isa, items=''):
    return f'''		{i(key)} = {{
			isa = {isa};
			buildActionMask = 2147483647;
			files = (
{items}			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
'''
phases = ''
for t, _, _, _ in TARGETS:
    full = t in FULL
    phases += phase(t+'src', 'PBXSourcesBuildPhase', ''.join(f'				{i(t+"bf"+f)},\n' for f in SHARED_IOS) if full else '')
    phases += phase(t+'fw', 'PBXFrameworksBuildPhase', f'				{i(t+"bfsparkle")},\n' if full else '')
    phases += phase(t+'res', 'PBXResourcesBuildPhase')
    phases += f'''		{i(t+'embed')} = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = (
{f"				{i(t+'bfsparkleembed')},{chr(10)}" if t in FULL else ''}			);
			name = "Embed Frameworks";
			runOnlyForDeploymentPostprocessing = 0;
		}};
'''
targets = ''.join(f'''		{i(t+'target')} = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {i(t+'cfgs')};
			buildPhases = (
				{i(t+'src')},
				{i(t+'fw')},
				{i(t+'res')},
				{i(t+'embed')},
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
{f"				{i('Sharedgroup')},{chr(10)}" if t in FULL else ''}				{i(t+'group')},
			);
			name = {t};
			productName = "{prod}";
			productReference = {i(t+'product')};
			productType = "com.apple.product-type.application";
		}};
''' for t, prod, _, _ in TARGETS)
cfgs = ''.join(cfg(t+'debug', 'Debug', settings(t, prod, bid + '.debug', ver)) + cfg(t+'release', 'Release', settings(t, prod, bid, ver)) for t, prod, bid, ver in TARGETS)
lists = cfglist('projcfgs', 'projdebug', 'projrelease') + ''.join(cfglist(t+'cfgs', t+'debug', t+'release') for t, _, _, _ in TARGETS)
ios_children = ''.join(f'				{i("ios"+f)},\n' for f in SHARED_IOS)
out = f'''// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
{buildfiles}/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{files}/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
{exceptions}/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
{groups}/* End PBXFileSystemSynchronizedRootGroup section */

{phases}
		{i('maingroup')} = {{
			isa = PBXGroup;
			children = (
				{i('Sharedgroup')},
				{''.join(f"{i(t+'group')},\n				" for t, _, _, _ in TARGETS)}{i('iosgroup')},
				{i('sparklefw')},
				{i('products')},
			);
			sourceTree = "<group>";
		}};
		{i('iosgroup')} = {{
			isa = PBXGroup;
			children = (
{ios_children}			);
			name = "Shared with the iPhone app";
			sourceTree = "<group>";
		}};
		{i('products')} = {{
			isa = PBXGroup;
			children = (
{''.join(f"				{i(t+'product')},\n" for t, _, _, _ in TARGETS)}			);
			name = Products;
			sourceTree = "<group>";
		}};
{targets}
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
{''.join(f"				{i(t+'target')},\n" for t, _, _, _ in TARGETS)}			);
		}};
{cfg('projdebug', 'Debug', debug)}{cfg('projrelease', 'Release', release)}{cfgs}{lists}	}};
	rootObject = {P};
}}
'''
proj = os.path.join(ROOT, 'FlagcastMac.xcodeproj')
os.makedirs(os.path.join(proj, 'xcshareddata', 'xcschemes'), exist_ok=True)
open(os.path.join(proj, 'project.pbxproj'), 'w').write(out)
for t, prod, _, _ in TARGETS:
    ref = f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{i(t+"target")}" BuildableName = "{prod}.app" BlueprintName = "{t}" ReferencedContainer = "container:FlagcastMac.xcodeproj"></BuildableReference>'
    open(os.path.join(proj, 'xcshareddata', 'xcschemes', f'{t}.xcscheme'), 'w').write(f'''<?xml version="1.0" encoding="UTF-8"?>
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
