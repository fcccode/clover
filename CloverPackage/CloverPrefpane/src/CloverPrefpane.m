//
//  CloverPrefpane.m
//  CloverPrefpane
//
//  Created by JrCs on 03/05/13.
//  Copyright (c) 2013 ProjectOSX. All rights reserved.
//

#import "CloverPrefpane.h"
#include <mach/mach_error.h>

#define kCloverInstaller @"com.projectosx.clover.installer"

// Global Variables
static const CFStringRef agentIdentifier=CFSTR("com.projectosx.Clover.Updater");
static const CFStringRef agentExecutable=CFSTR("/Library/Application Support/Clover/CloverUpdaterUtility");
static const CFStringRef checkIntervalKey=CFSTR("ScheduledCheckInterval");
static const CFStringRef lastCheckTimestampKey=CFSTR("LastCheckTimestamp");
static const CFStringRef efiDirPathKey=CFSTR("EFI Directory Path");

static const NSString* kLogLineCount = @"Clover.LogLineCount";
static const NSString* kLogEveryBoot = @"Clover.LogEveryBoot";
static const NSString* kBackupDirOnDestVol = @"Clover.BackupDirOnDestVol";
static const NSString* kKeepBackupLimit = @"Clover.KeepBackupLimit";
static const NSString* kMountEFI = @"Clover.MountEFI";
static const NSString* kNVRamDisk = @"Clover.NVRamDisk";

@implementation CloverPrefpane

@synthesize cloverLogLineCount        = _cloverLogLineCount;
@synthesize cloverLogEveryBootEnabled = _cloverLogEveryBootEnabled;
@synthesize cloverLogEveryBootLimit   = _cloverLogEveryBootLimit;
@synthesize cloverBackupDirOnDestVol  = _cloverBackupDirOnDestVol;
@synthesize cloverKeepBackupLimit     = _cloverKeepBackupLimit;

@synthesize diskutilList  = _diskutilList;
@synthesize efiPartitions = _efiPartitions;
@synthesize nvRamPartitions = _nvRamPartitions;
@synthesize cloverMountEfiPartition = _cloverMountEfiPartition;
@synthesize cloverNvRamDisk = _cloverNvRamDisk;

#pragma mark Properties

- (NSDictionary *)diskutilList
{
    if (_diskutilList == nil) {
        // Get diskutil list -plist output
        NSTask *task = [[NSTask alloc] init];

        [task setLaunchPath: @"/usr/sbin/diskutil"];
        [task setArguments:[NSArray arrayWithObjects: @"list", @"-plist", nil]];

        NSPipe *pipe = [NSPipe pipe];

        [task setStandardOutput: pipe];

        NSFileHandle *file = [pipe fileHandleForReading];

        [task launch];

        NSData *data = [file readDataToEndOfFile];

        _diskutilList = CFPropertyListCreateWithData(kCFAllocatorDefault, (CFDataRef)data, kCFPropertyListImmutable, NULL, NULL);

        [task release];
    }

    return _diskutilList;
}

// Hack to avoid warning generated by genstrings
#define GetLocalized\
String(key, comment)    NSLocalized\
StringFromTableInBundle(key, nil, self.bundle, comment)

#define AddMenuItemToSourceList(list, title, value) \
[list addObject:[NSDictionary dictionaryWithObjectsAndKeys: \
(title), @"Title", \
(value), @"Value", nil]]

- (NSArray*)efiPartitions
{
    if (_efiPartitions == nil) {
        NSMutableArray *list = [[NSMutableArray alloc] init];

        AddMenuItemToSourceList(list, GetLocalizedString(@"No",@"Not mounting EFI partition"), @"No");
        AddMenuItemToSourceList(list, GetLocalizedString(@"Boot Volume",@"EFI partition from boot volume"), @"Yes");

        NSArray *disksAndPartitions = [[self diskutilList] objectForKey:@"AllDisksAndPartitions"];
        if (disksAndPartitions != nil) {
            for (NSDictionary *diskEntry in disksAndPartitions) {

                NSString *content = [diskEntry objectForKey:@"Content"];

                if (content != nil) {
                    // Disk has partitions
                    if ([content isEqualToString:@"GUID_partition_scheme"] || [content isEqualToString:@"FDisk_partition_scheme"]) {

                        NSString *diskIdentifier = [diskEntry objectForKey:@"DeviceIdentifier"];
                        NSArray *partitions = [diskEntry objectForKey:@"Partitions"];

                        if (diskIdentifier != nil && partitions != nil) {
                            NSMutableArray *volumeNames = [[NSMutableArray alloc] init];
                            NSString *espIdentifier = nil;

                            for (NSDictionary *partitionEntry in partitions) {

                                NSString *content = [partitionEntry objectForKey:@"Content"];

                                if (content != nil && [content isEqualToString:@"EFI"]) {

                                    NSString *identifier = [partitionEntry objectForKey:@"DeviceIdentifier"];

                                    if (identifier != nil) {
                                        espIdentifier = [[self getPartitionProperties:identifier] objectForKey:@"UUID"];

                                        if (!espIdentifier) {
                                            espIdentifier = identifier;
                                        }
                                    }
                                }

                                NSString *volumeName = [partitionEntry objectForKey:@"VolumeName"];

                                if (volumeName) {
                                    [volumeNames addObject:volumeName];
                                }
                            }

                            if (espIdentifier) {
                                NSString *name = [NSString stringWithFormat:GetLocalizedString(@"ESP on [%@] %@", nil),
                                                  diskIdentifier, [volumeNames componentsJoinedByString:@", "]];
                                AddMenuItemToSourceList(list, name, espIdentifier);
                            }

                            [volumeNames release];
                        }
                    }
                }
            }
        }

        _efiPartitions = [NSArray arrayWithArray:list];
        [list release];
    }
    return _efiPartitions;
}

- (NSArray*)nvRamPartitions
{
    if (nil == _nvRamPartitions) {
        NSMutableArray *list = [[NSMutableArray alloc] init];

        AddMenuItemToSourceList(list, GetLocalizedString(@"Nowhere",nil), @"No");
        AddMenuItemToSourceList(list, GetLocalizedString(@"Default",nil), @"Yes");

        NSArray *disksAndPartitions = [[self diskutilList] objectForKey:@"AllDisksAndPartitions"];

        if (disksAndPartitions != nil) {
            for (NSDictionary *diskEntry in disksAndPartitions) {

                NSString *content = [diskEntry objectForKey:@"Content"];

                if (content != nil) {
                    // Disk has partitions
                    if ([content isEqualToString:@"GUID_partition_scheme"] || [content isEqualToString:@"FDisk_partition_scheme"]) {

                        NSArray *partitions = [diskEntry objectForKey:@"Partitions"];

                        if (partitions != nil) {
                            for (NSDictionary *partitionEntry in partitions) {

                                NSString *content = [partitionEntry objectForKey:@"Content"];

                                if (content != nil && ([content isEqualToString:@"Apple_HFS"]  ||
                                                       [content isEqualToString:@"Apple_Boot"] ||
                                                       [content isEqualToString:@"EFI"])) {

                                    NSString *identifier = [partitionEntry objectForKey:@"DeviceIdentifier"];

                                    if (identifier != nil) {
                                        NSDictionary *partitionProperties = [self getPartitionProperties:identifier];

                                        if (partitionProperties) {

                                            NSNumber *writable = [partitionProperties objectForKey:@"Writable"];

                                            if (writable != nil && [writable boolValue] == YES) {

                                                NSString *volumeName = [partitionEntry objectForKey:@"VolumeName"];
                                                if (volumeName == nil || [volumeName length] == 0) {
                                                    volumeName = [content isEqualToString:@"EFI"] ? @"ESP" : @"";
                                                }

                                                NSString *title = [NSString stringWithFormat:@"[%@] %@", identifier, volumeName];

                                                AddMenuItemToSourceList(list, title, identifier);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        _nvRamPartitions = [NSArray arrayWithArray:list];
        [list release];
    }

    return _nvRamPartitions;
}

-(void)setCloverLogLineCount:(NSNumber *)value
{
    if (!value)
        value=@0;
    if (![self.cloverLogLineCount isEqualToNumber:value]) {
        [_cloverLogLineCount release];
        _cloverLogLineCount = [value retain];

        [self setNVRamKey:kLogLineCount
                    Value:[NSString stringWithFormat:@"%ld", [value longValue]]];
    }
}

-(void)updateCloverLogEveryBoot
{
    NSString* logEveryBoot;
    if ([self.cloverLogEveryBootEnabled boolValue] == YES) {
        unsigned int logEveryBootLimit = [self.cloverLogEveryBootLimit unsignedIntValue];
        if (logEveryBootLimit > 0) {
            logEveryBoot = [NSString stringWithFormat:@"%d", logEveryBootLimit];
        }
        else
            logEveryBoot=@"Yes";
    }
    else
        logEveryBoot=@"";

    [self setNVRamKey:kLogEveryBoot Value:logEveryBoot];
}

- (void)setCloverLogEveryBootEnabled:(NSNumber *)value
{
    if (![_cloverLogEveryBootEnabled isEqualToNumber:value]) {
        [_cloverLogEveryBootEnabled release];
        _cloverLogEveryBootEnabled = [value retain];
        [self updateCloverLogEveryBoot];
    }
}

- (void)setCloverLogEveryBootLimit:(NSNumber *)value
{
    if (![self.cloverLogEveryBootLimit isEqualToNumber:value]) {
        [_cloverLogEveryBootLimit release];
        _cloverLogEveryBootLimit = [value retain];
        [self updateCloverLogEveryBoot];
    }
}

-(void)setCloverBackupDirOnDestVol:(NSNumber *)value
{
    if (!value)
        value=@NO;
    if (![self.cloverBackupDirOnDestVol isEqualToNumber:value]) {
        [_cloverBackupDirOnDestVol release];
        _cloverBackupDirOnDestVol = [value retain];
        NSString *backupDirOnDestVol = [value boolValue] ? @"Yes" : @"";
        [self setNVRamKey:kBackupDirOnDestVol
                    Value:backupDirOnDestVol];
    }
}

- (void)setCloverKeepBackupLimit:(NSNumber *)value
{
    if (!value)
        value=@0;
    if (![self.cloverKeepBackupLimit isEqualToNumber:value]) {
        [_cloverKeepBackupLimit release];
        _cloverKeepBackupLimit = [value retain];
        [self setNVRamKey:kKeepBackupLimit
                    Value:[NSString stringWithFormat:@"%@", value]];
    }
}


-(void)setCloverMountEfiPartition:(NSString *)value
{
    if (_cloverMountEfiPartition != value) {
        [_cloverMountEfiPartition release];
        _cloverMountEfiPartition = [value copy];
        [self setNVRamKey:kMountEFI Value:value];
    }
}

-(void)setCloverNvRamDisk:(NSString *)value
{
    if (_cloverNvRamDisk != value) {
        [_cloverNvRamDisk release];
        _cloverNvRamDisk = [value copy];
        [self setNVRamKey:kNVRamDisk Value:value];
    }
}

#pragma mark Methods

- (NSDictionary*)getPartitionProperties:(NSString*)bsdName
{
    CFMutableDictionaryRef	matchingDict;
    io_service_t			service;
    NSDictionary            *result = nil;

    matchingDict = IOBSDNameMatching(kIOMasterPortDefault, 0, [bsdName UTF8String]);

    if (matchingDict == NULL) {
        NSLog(@"IOBSDNameMatching returned a NULL dictionary");
    }
    else {
        // Fetch the object with the matching BSD node name.
		// Note that there should only be one match, so IOServiceGetMatchingService is used instead of
		// IOServiceGetMatchingServices to simplify the code.
        service = IOServiceGetMatchingService(kIOMasterPortDefault, matchingDict);

		if (IO_OBJECT_NULL == service) {
			NSLog(@"IOServiceGetMatchingService returned IO_OBJECT_NULL");
		}
		else {
			if (IOObjectConformsTo(service, "IOMedia")) {
                CFMutableDictionaryRef properties;
                IORegistryEntryCreateCFProperties(service,&properties, kCFAllocatorDefault, 0);
                result = [NSMakeCollectable(properties) autorelease];
            }
			IOObjectRelease(service);
		}
    }

    return result;
}


#pragma mark Events

// System Preferences calls this method when the pane is initialized.
- (id)initWithBundle:(NSBundle *)bundle {
    if ( ( self = [super initWithBundle:bundle] ) != nil ) {
        NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        NSString *agentsFolder = [[searchPaths objectAtIndex:0] stringByAppendingPathComponent:@"LaunchAgents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:agentsFolder withIntermediateDirectories:YES attributes:nil error:nil];
        agentPlistPath = [[NSString alloc]
                          initWithString:[[agentsFolder stringByAppendingPathComponent:(NSString *)agentIdentifier]
                                          stringByAppendingPathExtension:@"plist"]];

        // Allocate object for accessing IORegistry
        mach_port_t   masterPort;
        kern_return_t result = IOMasterPort(bootstrap_port, &masterPort);
        if (result != KERN_SUCCESS) {
            NSLog(@"Error getting the IOMaster port: %s", mach_error_string(result));
            exit(1);
        }

        _ioRegEntryRef = IORegistryEntryFromPath(masterPort, "IODeviceTree:/options");
        if (_ioRegEntryRef == 0) {
            NSLog(@"nvram is not supported on this system");
        }

        _diskutilList = nil;

        // Init NVRam variables fields
        [self initNVRamVariableFields];

    }
    return self;
}

- (void)mainViewDidLoad {
    BOOL plistExists;

    // Initialize revision fields
    NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, YES);
    NSString *preferenceFolder = [[searchPaths objectAtIndex:0] stringByAppendingPathComponent:@"Preferences"];
    NSString *cloverInstallerPlist = [[preferenceFolder stringByAppendingPathComponent:kCloverInstaller] stringByAppendingPathExtension:@"plist"];
    plistExists = [[NSFileManager defaultManager] fileExistsAtPath:cloverInstallerPlist];
    NSString* installedRevision = @"-";
    if (plistExists) {
        NSDictionary *dict = [[[NSDictionary alloc]
                              initWithContentsOfFile:cloverInstallerPlist] autorelease];
        NSNumber* revision = [dict objectForKey:@"CloverRevision"];
        if (revision)
            installedRevision = [revision stringValue];
    }
    [lastInstalledRevision setStringValue:installedRevision];

    NSString* bootedRevision = @"-";
    io_registry_entry_t ioRegistryEFI = IORegistryEntryFromPath(kIOMasterPortDefault, "IODeviceTree:/efi/platform");
    if (ioRegistryEFI) {
        CFStringRef nameRef = CFStringCreateWithCString(kCFAllocatorDefault, "clovergui-revision",
                                                        kCFStringEncodingUTF8);
        if (nameRef) {
            CFTypeRef valueRef = IORegistryEntryCreateCFProperty(ioRegistryEFI, nameRef, 0, 0);
            CFRelease(nameRef);
            if (valueRef) {
                // Get the OF variable's type.
                CFTypeID typeID = CFGetTypeID(valueRef);
                if (typeID == CFDataGetTypeID())
                    bootedRevision = [NSString stringWithFormat:@"%u",*((uint32_t*)CFDataGetBytePtr(valueRef))];
                CFRelease(valueRef);
            }
        }
        IOObjectRelease(ioRegistryEFI);
    }
    [lastBootedRevision setStringValue:bootedRevision];

    // Initialize popUpCheckInterval
    unsigned int checkInterval =
        [self getUIntPreferenceKey:checkIntervalKey forAppID:agentIdentifier withDefault:0];
    [popUpCheckInterval selectItemWithTag:checkInterval];
    
    // Initialize LastRunDate
    unsigned int lastCheckTimestamp =
        [self getUIntPreferenceKey:lastCheckTimestampKey forAppID:agentIdentifier withDefault:0];
    if (lastCheckTimestamp == 0) {
        [LastRunDate setStringValue:@"-"];
    } else {
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:lastCheckTimestamp];
        [LastRunDate setStringValue:[LastRunDate.formatter stringFromDate:date]];

    }
    // Enable the checkNowButton if executable is present
    [checkNowButton setEnabled:[[NSFileManager defaultManager] fileExistsAtPath:(NSString*)agentExecutable]];
    
    // Get EFI Path
    NSString* efiDir=[self getStringPreferenceKey:efiDirPathKey
                                         forAppID:(CFStringRef)[self.bundle bundleIdentifier]
                                      withDefault:CFSTR("/")];
    [_EFIPathControl setURL:[NSURL fileURLWithPath:efiDir]];
    [self initThemeTab:efiDir];

    // Setup security.
	AuthorizationItem items = {kAuthorizationRightExecute, 0, NULL, 0};
	AuthorizationRights rights = {1, &items};
	[authView setAuthorizationRights:&rights];
	authView.delegate = self;
	[authView updateStatus:nil];

    plistExists = [[NSFileManager defaultManager] fileExistsAtPath:agentPlistPath];
    if (plistExists && checkInterval == 0) {
        [[NSFileManager defaultManager] removeItemAtPath:agentPlistPath error:nil];
    }
}

-(void) initNVRamVariableFields
{
    NSString *value;

    value = [self getNVRamKey:kLogLineCount];
    _cloverLogLineCount = [[NSNumber numberWithLong:[value longLongValue]] retain];

    value = [self getNVRamKey:kLogEveryBoot];
    if ([value length] == 0) {
        _cloverLogEveryBootEnabled = @NO;
        _cloverLogEveryBootLimit  = @0;
    }
    else {
        _cloverLogEveryBootEnabled = [([value isCaseInsensitiveLike:@"No"] ? @NO : @YES) retain];
        _cloverLogEveryBootLimit   = [[NSNumber numberWithInteger:[value integerValue]] retain];
    }

    value = [self getNVRamKey:kBackupDirOnDestVol];
    _cloverBackupDirOnDestVol = [([value isCaseInsensitiveLike:@"Yes"] ? @YES : @NO) retain];

    value = [self getNVRamKey:kKeepBackupLimit];
    if ([value length] == 0)
        _cloverKeepBackupLimit = @0;
    else
        _cloverKeepBackupLimit = [[NSNumber numberWithInteger:[value integerValue]] retain];


    value = [self getNVRamKey:kMountEFI];
    self.cloverMountEfiPartition = value;

    value = [self getNVRamKey:kNVRamDisk];
    self.cloverNvRamDisk = value;
}


#pragma mark -
#pragma mark General Tab Methods
- (IBAction) configureAutomaticUpdates:(id)sender {
    CFDictionaryRef launchInfo = SMJobCopyDictionary(kSMDomainUserLaunchd, agentIdentifier);
    if (launchInfo != NULL) {
        CFRelease(launchInfo);
        CFErrorRef error = NULL;
        if (!SMJobRemove(kSMDomainUserLaunchd, agentIdentifier, NULL, YES, &error))
            NSLog(@"Error in SMJobRemove: %@", error);
        if (error)
            CFRelease(error);
    }

	NSInteger checkInterval = [sender tag];
	[self setPreferenceKey:checkIntervalKey forAppID:agentIdentifier fromInt:(int)checkInterval];


    if (checkInterval > 0 && [[NSFileManager defaultManager] fileExistsAtPath:(NSString*)agentExecutable]) {
        // Create a new plist
        NSArray* call = [NSArray arrayWithObjects:
                         (NSString *)agentExecutable,
                         @"startup",
                         nil];
        NSDictionary *plist = [NSDictionary dictionaryWithObjectsAndKeys:
                               (NSString *)agentIdentifier, @"Label",
                               [NSNumber numberWithInteger:checkInterval], @"StartInterval",
                               [NSNumber numberWithBool:YES], @"RunAtLoad",
                               (NSString *)agentExecutable, @"Program",
                               call, @"ProgramArguments",
                               nil];
        [plist writeToFile:agentPlistPath atomically:YES];

		CFErrorRef error = NULL;
		if (!SMJobSubmit(kSMDomainUserLaunchd, (CFDictionaryRef)plist, NULL, &error)) {
			if (error) {
				NSLog(@"Error in SMJobSubmit: %@", error);
			} else
				NSLog(@"Error in SMJobSubmit without details. Check /var/db/launchd.db/com.apple.launchd.peruser.NNN/overrides.plist for %@ set to disabled.", agentIdentifier);
		}
		if (error)
			CFRelease(error);
    } else {
        // Remove the plist
        [[NSFileManager defaultManager] removeItemAtPath:agentPlistPath error:nil];
    }
    CFPreferencesAppSynchronize(agentIdentifier); // Force the preferences to be save to disk
}

- (IBAction)checkNow:(id)sender {
    [[NSWorkspace sharedWorkspace] launchApplication:(NSString*)agentExecutable];
}


- (BOOL)isUnlocked {
	return [authView authorizationState] == SFAuthorizationViewUnlockedState;
}

#pragma mark -
#pragma mark Theme Tab Methods

- (void) initThemeTab:(NSString*) efiDir {

    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDir = NO;

    [_cloverThemeComboBox removeAllItems]; // Remove all theme names if exists

    NSString *themesDir = [efiDir stringByAppendingPathComponent:@"CLOVER/Themes"];
    [fileManager fileExistsAtPath:themesDir isDirectory:(&isDir)];
    [_themeWarning setHidden:isDir];

    // get the list of all files and directories
    NSMutableArray *themes = [[[NSMutableArray alloc] init] autorelease];

    NSArray *fileList = [fileManager contentsOfDirectoryAtPath:themesDir error:nil];
    if (fileList) {
        for(NSString *file in fileList) {
            NSString *path = [[themesDir stringByAppendingPathComponent:file]
                               stringByAppendingPathComponent:@"theme.plist"];
            if ([fileManager fileExistsAtPath:path]) {
                [themes addObject:file];
            }
        }
    }
    else {
        // Try to get installed themes
        NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, YES);
        NSString *preferenceFolder = [[searchPaths objectAtIndex:0] stringByAppendingPathComponent:@"Preferences"];
        NSString *cloverInstallerPlist = [[preferenceFolder stringByAppendingPathComponent:kCloverInstaller] stringByAppendingPathExtension:@"plist"];
        NSDictionary *dict = [[[NSDictionary alloc]
                              initWithContentsOfFile:cloverInstallerPlist] autorelease];
        if (dict) {
            NSArray *installedThemes = [dict objectForKey:@"InstalledThemes"];
            [themes addObjectsFromArray:installedThemes];
        }
        else {
            // Get default themes from bundle
            NSString* defaultThemePlistPath = [self.bundle pathForResource:@"DefaultThemes.plist" ofType:@"plist"];
            NSDictionary *dict = [[[NSDictionary alloc]
                                  initWithContentsOfFile:defaultThemePlistPath] autorelease];
            if (dict) {
                NSArray *defaultThemes = [dict objectForKey:@"Default Themes"];
                if (defaultThemes)
                    [themes addObjectsFromArray:defaultThemes];
            }
        }
    }

    NSString* currentTheme = [self getNVRamKey:@"Clover.Theme"];
    if (currentTheme && [themes indexOfObject:currentTheme] == NSNotFound)
        [themes addObject:currentTheme];

    NSArray *sortedThemes = [themes sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [_cloverThemeComboBox addItemsWithObjectValues:sortedThemes];
    if (currentTheme) {
        [_cloverThemeComboBox selectItemWithObjectValue:currentTheme];
        [self updateThemeTab:currentTheme];
    }
}

- (void) updateThemeTab:(NSString*) themeName {
    NSString *efiDir    = [[_EFIPathControl URL] path];
    NSString *themeDir  = [[efiDir stringByAppendingPathComponent:@"CLOVER/Themes"]
                           stringByAppendingPathComponent:themeName];
    // Load the theme.plist file
    NSString *themePlistPath = [themeDir stringByAppendingPathComponent:@"theme.plist"];

    NSMutableDictionary *newThemeInfo = [NSMutableDictionary dictionaryWithContentsOfFile:themePlistPath];
    if (newThemeInfo)
        self.themeInfo = newThemeInfo;
    else
        self.themeInfo = [NSMutableDictionary dictionaryWithCapacity:16]; // 16 entries for the moment

    NSString *imagePath = [themeDir stringByAppendingPathComponent:@"screenshot.png"];
    NSNumber *previewAvailable = @YES;
    if (![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        imagePath = [self.bundle pathForResource:@"NoPreview" ofType:@"png"];
        previewAvailable = @NO;
    }
    [self.themeInfo setObject:previewAvailable forKey:@"PreviewAvailable"];

    [self.themeInfo setObject:[[NSImage alloc] initWithContentsOfFile:imagePath] forKey:@"Preview"];

    if (![self.themeInfo objectForKey:@"Author"])
        [self.themeInfo setObject:GetLocalizedString(@"Unknown",nil) forKey:@"Author"];

    if (![self.themeInfo objectForKey:@"Year"])
        [self.themeInfo setObject:GetLocalizedString(@"Unknown",nil) forKey:@"Year"];

    if (![self.themeInfo objectForKey:@"Description"])
        [self.themeInfo setObject:GetLocalizedString(@"No description available",nil) forKey:@"Description"];

    // Update NVRam
    NSString *oldValue = [self getNVRamKey:@"Clover.Theme"];
    if ((oldValue.length != 0 || themeName.length != 0) &&
        ![oldValue isEqualToString:themeName]) {
        if ([self setNVRamKey:@"Clover.Theme" Value:themeName] != 0) {
            [_cloverThemeComboBox setStringValue:oldValue];
            [self updateThemeTab:oldValue];
        }
    }
}

- (IBAction)showPathOpenPanel:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setResolvesAliases:YES];

    NSString *panelTitle = GetLocalizedString(@"Select the EFI directory", @"Title for the open panel");
    [panel setTitle:panelTitle];

    NSString *promptString = GetLocalizedString(@"Set EFI directory", @"Prompt for the open panel prompt");
    [panel setPrompt:promptString];

    [panel beginSheetModalForWindow:[sender window] completionHandler:^(NSInteger result) {

        // Hide the open panel.
        [panel orderOut:self];

        // If the return code wasn't OK, don't do anything.
        if (result != NSOKButton) {
            return;
        }
        // Get the first URL returned from the Open Panel and set it at the first path component of the control.
        NSURL *url = [[panel URLs] objectAtIndex:0];
        [_EFIPathControl setURL:url];

        NSString *efiDir = [url path];
        [self setPreferenceKey:efiDirPathKey
                      forAppID:(CFStringRef)[self.bundle bundleIdentifier]
                    fromString:(CFStringRef)efiDir];
        CFPreferencesAppSynchronize((CFStringRef)[self.bundle bundleIdentifier]); // Force the preferences to be save to disk

        [self initThemeTab:efiDir];
    }];
}

- (IBAction)themeComboBox:(NSComboBox*)sender {
    NSString *themeName = [sender stringValue];
    [self updateThemeTab:themeName];
}

#pragma mark -
#pragma mark Authorization delegates

//
// SFAuthorization delegates
//
- (void)authorizationViewDidAuthorize:(SFAuthorizationView *)view {
}

- (void)authorizationViewDidDeauthorize:(SFAuthorizationView *)view {
}


//
// NVRAM methods
//
#pragma mark -
#pragma mark NVRam methods

// Get NVRAM value
-(NSString*) getNVRamKey:(const NSString*)key {
    NSString*   result = @"";

    CFTypeRef valueRef = IORegistryEntryCreateCFProperty(_ioRegEntryRef, (CFStringRef)key, 0, 0);
    if (valueRef == 0) return result;

    // Get the OF variable's type.
    CFTypeID typeID = CFGetTypeID(valueRef);

    if (typeID == CFDataGetTypeID())
        result = [NSString stringWithUTF8String:(const char*)CFDataGetBytePtr(valueRef)];

    CFRelease(valueRef);

    return result;
}

// Set NVRAM key/value pair
-(OSErr) setNVRamKey:(const NSString*)key Value:(NSString*)value {

    OSErr processError = 0;

    if (key) {
        if (!value)
            value=@"";
        NSString *oldValue = [self getNVRamKey:key];
        if ((oldValue.length != 0 || value.length != 0) &&
            ![oldValue isEqualToString:value]) {

            // Size for key=value + null terminal char
            size_t len = [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1
                         + [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
            char* nvram_arg=(char*) malloc(sizeof(char) * len);
            snprintf(nvram_arg, len, "%s=%s", [key UTF8String], [value UTF8String]);

            // Need 2 parameters: key=value and NULL
            const char **argv = (const char **)malloc(sizeof(char *) * 2);
            argv[0] = nvram_arg;
            argv[1] = NULL;

            processError = AuthorizationExecuteWithPrivileges([[authView authorization] authorizationRef], [@"/usr/sbin/nvram" UTF8String],
                                                              kAuthorizationFlagDefaults, (char *const *)argv, nil);

            if (processError != errAuthorizationSuccess)
                NSLog(@"Error trying to set nvram %s:%d", nvram_arg, processError);

            free(argv);
            free(nvram_arg);
        }
    }
    return processError;
}

//
// Preferences methods
//
#pragma mark -
#pragma mark Preferences methods

// get and set preference keys functions idea taken from:
// http://svn.perian.org/branches/perian-1.1/CPFPerianPrefPaneController.m
- (unsigned int)getUIntPreferenceKey:(CFStringRef)key
                            forAppID:(CFStringRef)appID
                         withDefault:(unsigned int)defaultValue
{
	CFPropertyListRef value;
	unsigned int ret = defaultValue;
	
	value = CFPreferencesCopyAppValue(key, appID);
	if (value && CFGetTypeID(value) == CFNumberGetTypeID())
		CFNumberGetValue(value, kCFNumberIntType, &ret);
	
	if (value)
		CFRelease(value);
	
	return ret;
}

- (void)setPreferenceKey:(CFStringRef)key
                forAppID:(CFStringRef)appID
                 fromInt:(int)value
{
	CFNumberRef numRef = CFNumberCreate(NULL, kCFNumberIntType, &value);
	CFPreferencesSetAppValue(key, numRef, appID);
	CFRelease(numRef);
}

- (NSString *)getStringPreferenceKey:(CFStringRef)key
                            forAppID:(CFStringRef)appID
                         withDefault:(CFStringRef)defaultValue
{
	CFPropertyListRef value;
	NSString *ret = nil;

	value = CFPreferencesCopyAppValue(key, appID);
	if(value && CFGetTypeID(value) == CFStringGetTypeID())
		ret = [NSString stringWithString:(NSString *)value];
    else
        ret = [NSString stringWithString:(NSString *)defaultValue];

	if(value)
		CFRelease(value);

	return ret;
}

- (void)setPreferenceKey:(CFStringRef)key
                forAppID:(CFStringRef)appID
              fromString:(CFStringRef)value
{
	CFPreferencesSetAppValue(key, value, appID);
}


@end