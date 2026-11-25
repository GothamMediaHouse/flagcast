#!/usr/bin/env python3
# Writes FlagcastStaff.xcodeproj: Flagcast Manager for iPhone and iPad (native SwiftUI, iOS 17+), and the last
# Flagcast Admin (it only says Admin is now in Manager).
#   python3 tools/make-project.py        (from apps/flagcast-staff-ios)
# Manager/ and Admin/ are synchronized groups: add Swift files there and Xcode picks them up.
# The tournament model, scoring math and live feed come from the iPhone player app, and the desk model, server calls,
# Admin model, course pictures and TV logic from the Mac app, by reference (SHARED).
import hashlib, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def i(name): return hashlib.md5(('flagcast-staff-ios:' + name).encode()).hexdigest()[:24].upper()

TEAM = 'C8KXPB4QNA'
# (target, product name, bundle id, version, build, Info.plist)
TARGETS = [
    ('Manager', 'Flagcast Manager', 'app.flagcast.manager', '2.9.12', '12', 'Manager-Info.plist'),
    # Flagcast Admin is retired (Admin lives inside Manager): no target, so it can't be built or sent to TestFlight.
    # Its last build was 1.2.0 (4); the Admin/ folder stays for reference.
]
FULL = {'Manager'}
SHARED = [
    '../flagcast-ios/Flagcast/Model/Models.swift', '../flagcast-ios/Flagcast/Model/Core.swift',
    '../flagcast-ios/Flagcast/Net/Server.swift', '../flagcast-ios/Flagcast/Net/EventFeed.swift',
    '../flagcast-mac/Shared/Net.swift', '../flagcast-mac/Shared/Desk.swift', '../flagcast-mac/Shared/Route.swift',
    '../flagcast-mac/Shared/UI.swift', '../flagcast-mac/Shared/Geo.swift', '../flagcast-mac/Shared/CourseImages.swift',
    '../flagcast-mac/Shared/Desk/DeskDoc.swift', '../flagcast-mac/Shared/Desk/DeskNav.swift', '../flagcast-mac/Shared/Desk/ScreenLogic.swift', '../flagcast-mac/Shared/Desk/ClubTVs.swift',
    '../flagcast-mac/Shared/Desk/PinBoard.swift', '../flagcast-mac/Shared/Desk/GroupCard.swift', '../flagcast-mac/Shared/Desk/ContestCheck.swift',
    '../flagcast-mac/Shared/Admin/AdminModel.swift', '../flagcast-mac/Manager/AppModel.swift', '../flagcast-mac/Shared/AppleSignIn.swift',
    '../flagcast-mac/Shared/Branding.swift', '../flagcast-mac/Shared/DayOf.swift', '../flagcast-mac/Shared/Admin/EventDay.swift',
    '../flagcast-ios/Flagcast/Views/GoLiveView.swift',
]
# Swift packages: HaishinKit sends Go live video (SRT, or RTMPS) from the camera
PACKAGES = [('HaishinKit.swift', 'https://github.com/HaishinKit/HaishinKit.swift.git', '2.3.2', ['HaishinKit', 'SRTHaishinKit', 'RTMPHaishinKit'])]
PRODUCTS = [(pkg, prod) for pkg, _, _, prods in PACKAGES for prod in prods]
FONTS = ['../flagcast-mac/Shared/Fonts/BarlowCondensed-Bold.ttf', '../flagcast-mac/Shared/Fonts/BarlowCondensed-SemiBold.ttf']

def settings(t, prod, bid, ver, build, plist):
    ent = '				CODE_SIGN_ENTITLEMENTS = Manager.entitlements;\n' if t == 'Manager' else ''
    return f'''				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
{ent}				CURRENT_PROJECT_VERSION = {build};
				DEVELOPMENT_TEAM = {TEAM};
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = "{plist}";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = {ver};
				PRODUCT_BUNDLE_IDENTIFIER = {bid};
				PRODUCT_NAME = "{prod}";
				SDKROOT = iphoneos;
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
'''
common = '''				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
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
def kind(f): return 'sourcecode.swift' if f.endswith('.swift') else 'file'
P = i('project')
files = ''.join(f'''		{i(t+'product')} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "{prod}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
''' for t, prod, *_ in TARGETS)
files += ''.join(f'''		{i('ref'+f)} = {{isa = PBXFileReference; lastKnownFileType = {kind(f)}; name = {os.path.basename(f)}; path = "{f}"; sourceTree = SOURCE_ROOT; }};
''' for f in SHARED + FONTS)
buildfiles = ''.join(f'''		{i(t+'bf'+f)} = {{isa = PBXBuildFile; fileRef = {i('ref'+f)}; }};
''' for t, *_ in TARGETS if t in FULL for f in SHARED + FONTS)
buildfiles += ''.join(f'''		{i(t+'pbf'+prod)} = {{isa = PBXBuildFile; productRef = {i('prod'+prod)}; }};
''' for t, *_ in TARGETS if t in FULL for _, prod in PRODUCTS)
groups = ''.join(f'''		{i(t+'group')} = {{
			isa = PBXFileSystemSynchronizedRootGroup;
			path = {t};
			sourceTree = "<group>";
		}};
''' for t, *_ in TARGETS)
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
for t, *_ in TARGETS:
    full = t in FULL
    phases += phase(t+'src', 'PBXSourcesBuildPhase', ''.join(f'				{i(t+"bf"+f)},\n' for f in SHARED) if full else '')
    phases += phase(t+'fw', 'PBXFrameworksBuildPhase', ''.join(f'				{i(t+"pbf"+prod)},\n' for _, prod in PRODUCTS) if full else '')
    phases += phase(t+'res', 'PBXResourcesBuildPhase', ''.join(f'				{i(t+"bf"+f)},\n' for f in FONTS) if full else '')
targets = ''.join(f'''		{i(t+'target')} = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {i(t+'cfgs')};
			buildPhases = (
				{i(t+'src')},
				{i(t+'fw')},
				{i(t+'res')},
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{i(t+'group')},
			);
			name = {t};
			packageProductDependencies = (
{''.join(f"				{i('prod'+p)},{chr(10)}" for _, p in PRODUCTS) if t in FULL else ''}			);
			productName = "{prod}";
			productReference = {i(t+'product')};
			productType = "com.apple.product-type.application";
		}};
''' for t, prod, *_ in TARGETS)
cfgs = ''.join(cfg(t+'debug', 'Debug', settings(t, prod, bid, ver, b, pl)) + cfg(t+'release', 'Release', settings(t, prod, bid, ver, b, pl)) for t, prod, bid, ver, b, pl in TARGETS)
lists = cfglist('projcfgs', 'projdebug', 'projrelease') + ''.join(cfglist(t+'cfgs', t+'debug', t+'release') for t, *_ in TARGETS)
shared_children = ''.join(f'				{i("ref"+f)},\n' for f in SHARED + FONTS)
pkgs = ''.join(f'''		{i('pkg'+n)} = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "{url}";
			requirement = {{
				kind = exactVersion;
				version = {ver};
			}};
		}};
''' for n, url, ver, _ in PACKAGES) + ''.join(f'''		{i('prod'+prod)} = {{
			isa = XCSwiftPackageProductDependency;
			package = {i('pkg'+pkg)};
			productName = {prod};
		}};
''' for pkg, prod in PRODUCTS)
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

/* Begin PBXFileSystemSynchronizedRootGroup section */
{groups}/* End PBXFileSystemSynchronizedRootGroup section */

{phases}
		{i('maingroup')} = {{
			isa = PBXGroup;
			children = (
{''.join(f"				{i(t+'group')},{chr(10)}" for t, *_ in TARGETS)}				{i('sharedgroup')},
				{i('products')},
			);
			sourceTree = "<group>";
		}};
		{i('sharedgroup')} = {{
			isa = PBXGroup;
			children = (
{shared_children}			);
			name = "Shared with the iPhone and Mac apps";
			sourceTree = "<group>";
		}};
		{i('products')} = {{
			isa = PBXGroup;
			children = (
{''.join(f"				{i(t+'product')},{chr(10)}" for t, *_ in TARGETS)}			);
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
			packageReferences = (
{''.join(f"				{i('pkg'+n)},{chr(10)}" for n, *_ in PACKAGES)}			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {i('products')};
			projectDirPath = "";
			projectRoot = "";
			targets = (
{''.join(f"				{i(t+'target')},{chr(10)}" for t, *_ in TARGETS)}			);
		}};
{cfg('projdebug', 'Debug', debug)}{cfg('projrelease', 'Release', release)}{cfgs}{lists}{pkgs}	}};
	rootObject = {P};
}}
'''
proj = os.path.join(ROOT, 'FlagcastStaff.xcodeproj')
os.makedirs(os.path.join(proj, 'xcshareddata', 'xcschemes'), exist_ok=True)
open(os.path.join(proj, 'project.pbxproj'), 'w').write(out)
for t, prod, *_ in TARGETS:
    ref = f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{i(t+"target")}" BuildableName = "{prod}.app" BlueprintName = "{t}" ReferencedContainer = "container:FlagcastStaff.xcodeproj"></BuildableReference>'
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
