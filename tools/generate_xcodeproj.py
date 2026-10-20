#!/usr/bin/env python3
"""Deterministically regenerate the self-contained Xcode project. Requires Python 3."""
from pathlib import Path
import hashlib
import re

BASE=Path(__file__).resolve().parents[1]
APP=BASE/'ReFindOne'
SWIFT=sorted(APP.rglob('*.swift'))
VERSION=(BASE/'VERSION').read_text().strip()
assert re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?', VERSION), 'Invalid release version'
assert len(SWIFT)>5

def ident(name):
    return hashlib.sha1(('refind:'+name).encode()).hexdigest().upper()[:24]

def oid(name): return ident(name)

def ref(line): return f'{oid(line)} /* {line.split("/")[-1]} */'

def q(value): return '"'+str(value).replace('\\','\\\\').replace('"','\\"')+'"'
objects=[]
def obj(name, lines, comment=None):
    objects.append(f'\t\t{oid(name)} /* {comment or name.split("/")[-1]} */ = {{\n' +
                   ''.join('\t\t\t'+line+'\n' for line in lines) + '\t\t};\n')

for file in SWIFT:
    relative=file.relative_to(APP).as_posix()
    obj('file/'+relative, ['isa = PBXFileReference;', 'lastKnownFileType = sourcecode.swift;',
                           f'path = {q(file.name)};', 'sourceTree = "<group>";'], file.name)
    obj('build/'+relative,['isa = PBXBuildFile;', f'fileRef = {ref("file/"+relative)};'], file.name+' in Sources')
obj('file/Assets.xcassets',['isa = PBXFileReference;', 'lastKnownFileType = folder.assetcatalog;',
                            'path = Assets.xcassets;', 'sourceTree = "<group>";'],'Assets.xcassets')
obj('build/Assets.xcassets',['isa = PBXBuildFile;',f'fileRef = {ref("file/Assets.xcassets")};'],'Assets.xcassets in Resources')
obj('file/Info.plist',['isa = PBXFileReference;', 'lastKnownFileType = text.plist.xml;',
                         'path = Info.plist;', 'sourceTree = "<group>";'],'Info.plist')
obj('product/app',['isa = PBXFileReference;', 'explicitFileType = wrapper.application;',
                   'includeInIndex = 0;', 'path = ReFindOne.app;', 'sourceTree = BUILT_PRODUCTS_DIR;'],'ReFindOne.app')

folders=sorted({f.parent.relative_to(APP).as_posix() for f in SWIFT})
for folder in folders:
    files=[f for f in SWIFT if f.parent.relative_to(APP).as_posix()==folder]
    obj('group/'+folder,['isa = PBXGroup;',
        'children = (']+[f'\t{ref("file/"+f.relative_to(APP).as_posix())},' for f in files]+[
        ');',f'path = {q(folder)};', 'sourceTree = "<group>";'], folder)
obj('group/Assets',['isa = PBXGroup;', 'children = (', f'\t{ref("file/Assets.xcassets")},',
    f'\t{ref("file/Info.plist")},',');','sourceTree = "<group>";'],'Assets')
obj('group/app',['isa = PBXGroup;', 'children = ('] + [f'\t{ref("group/"+folder)},' for folder in folders] +
    [f'\t{ref("file/Assets.xcassets")},',f'\t{ref("file/Info.plist")},',');','path = ReFindOne;', 'sourceTree = "<group>";'],'ReFindOne')
obj('group/products',['isa = PBXGroup;', 'children = (',f'\t{ref("product/app")},',');','name = Products;', 'sourceTree = "<group>";'],'Products')
obj('group/root',['isa = PBXGroup;', 'children = (',f'\t{ref("group/app")},',f'\t{ref("group/products")},',');','sourceTree = "<group>";'],'Root')
obj('phase/sources',['isa = PBXSourcesBuildPhase;', 'buildActionMask = 2147483647;', 'files = (']+
    [f'\t{ref("build/"+f.relative_to(APP).as_posix())},' for f in SWIFT]+
    [');','runOnlyForDeploymentPostprocessing = 0;'],'Sources')
obj('phase/resources',['isa = PBXResourcesBuildPhase;', 'buildActionMask = 2147483647;', 'files = (',
    f'\t{ref("build/Assets.xcassets")},',');','runOnlyForDeploymentPostprocessing = 0;'],'Resources')
obj('phase/frameworks',['isa = PBXFrameworksBuildPhase;', 'buildActionMask = 2147483647;',
                        'files = ();','runOnlyForDeploymentPostprocessing = 0;'],'Frameworks')

for mode in ['Debug','Release']:
    obj('config/project/'+mode,['isa = XCBuildConfiguration;', 'buildSettings = {',
        '\tALWAYS_SEARCH_USER_PATHS = NO;', '\tCLANG_ENABLE_MODULES = YES;',
        '\tCLANG_ENABLE_OBJC_ARC = YES;', '\tSDKROOT = iphoneos;',
        '\tSWIFT_VERSION = 5.0;', '\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;',
        '\tTARGETED_DEVICE_FAMILY = "1,2";',
        '\tENABLE_USER_SCRIPT_SANDBOXING = YES;',
        f'\tSWIFT_OPTIMIZATION_LEVEL = {q("-Onone" if mode=="Debug" else "-O")};',
        '\tDEBUG_INFORMATION_FORMAT = dwarf-with-dsym;',
        '};', f'name = {mode};'],'Project '+mode)
    obj('config/target/'+mode,['isa = XCBuildConfiguration;', 'buildSettings = {',
        '\tPRODUCT_NAME = "$(TARGET_NAME)";',
        '\tPRODUCT_BUNDLE_IDENTIFIER = dev.refind.one;',
        '\tGENERATE_INFOPLIST_FILE = NO;',
        '\tINFOPLIST_FILE = ReFindOne/Info.plist;',
        '\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;',
        '\tSWIFT_VERSION = 5.0;',
        '\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;',
        '\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";',
        '\tTARGETED_DEVICE_FAMILY = "1,2";',
        f'\tMARKETING_VERSION = {VERSION.split("-")[0]};',
        f'\tREFIND_RELEASE_VERSION = {q(VERSION)};',
        '\tCURRENT_PROJECT_VERSION = 3;',
        '\tCODE_SIGN_STYLE = Automatic;',
        '\tOTHER_LDFLAGS = ("$(inherited)", "-lsqlite3");',
        f'\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = {q("DEBUG" if mode=="Debug" else "")};',
        '};', f'name = {mode};'],'App '+mode)
for target in ['project','target']:
    obj('configlist/'+target,['isa = XCConfigurationList;', 'buildConfigurations = (',
        f'\t{ref("config/"+target+"/Debug")},',f'\t{ref("config/"+target+"/Release")},',
        ');','defaultConfigurationIsVisible = 0;', 'defaultConfigurationName = Release;'],target+' configs')
obj('target/app',['isa = PBXNativeTarget;',f'buildConfigurationList = {ref("configlist/target")};',
    'buildPhases = (', f'\t{ref("phase/sources")},',f'\t{ref("phase/frameworks")},',
    f'\t{ref("phase/resources")},',');','buildRules = ();','dependencies = ();',
    'name = ReFindOne;', f'productReference = {ref("product/app")};',
    'productName = ReFindOne;', 'productType = "com.apple.product-type.application";'],'ReFindOne')
obj('project',['isa = PBXProject;', f'buildConfigurationList = {ref("configlist/project")};',
    'compatibilityVersion = "Xcode 14.0";', 'developmentRegion = ru;', 'hasScannedForEncodings = 0;',
    'knownRegions = (ru, en, Base);',f'mainGroup = {ref("group/root")};',
    f'productRefGroup = {ref("group/products")};','projectDirPath = "";',
    'projectRoot = "";', 'targets = (',f'\t{ref("target/app")},',');',
    'attributes = {','\tBuildIndependentTargetsInParallel = YES;',
    f'\tTargetAttributes = {{ {oid("target/app")} = {{ CreatedOnToolsVersion = 16.0; }}; }};',
    '};'],'Project')

project='// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'
project+=''.join(objects)+'\t};\n'+f'\trootObject = {ref("project")};\n'+'}\n'
output=BASE/'ReFindOne.xcodeproj'/'project.pbxproj'
output.write_text(project, newline='\n')
print(f'Created {output} with {len(SWIFT)} Swift files')
