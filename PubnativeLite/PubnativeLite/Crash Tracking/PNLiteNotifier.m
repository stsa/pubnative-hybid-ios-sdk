//
//  Copyright © 2018 PubNative. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "PNLiteNotifier.h"
#import "PNLiteConnectivity.h"
#import "PNLiteCrashTracker.h"
#import "PNLiteCrashSentry.h"
#import "PNLiteHandledState.h"
#import "PNLiteCrashLogger.h"
#import "PNLiteKeys.h"
#import "PNLiteSessionTracker.h"
#import "PNLiteSessionTrackingApiClient.h"
#import "PNLite_RFC3339DateTool.h"

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#elif TARGET_OS_MAC
#import <AppKit/AppKit.h>
#endif

NSString *const PNLITE_NOTIFIER_VERSION = @"5.15.4";
NSString *const PNLITE_NOTIFIER_URL = @"https://github.com/bugsnag/bugsnag-cocoa";
NSString *const PNLITE_BSTabCrash = @"crash";
NSString *const PNLITE_BSAttributeDepth = @"depth";
NSString *const PNLITE_BSEventLowMemoryWarning = @"lowMemoryWarning";

static NSInteger const PNLITE_NotifierStackFrameCount = 5;

struct pnlite_data_t {
    // Contains the state of the event (handled/unhandled)
    char *handledState;
    // Contains the user-specified metaData, including the user tab from config.
    char *metaDataJSON;
    // Contains the PNLite configuration, all under the "config" tab.
    char *configJSON;
    // Contains notifier state, under "deviceState" and crash-specific
    // information under "crash".
    char *stateJSON;
    // Contains properties in the PNLite payload overridden by the user before
    // it was sent
    char *userOverridesJSON;
    // User onCrash handler
    void (*onCrash)(const PNLite_KSCrashReportWriter *writer);
};

static struct pnlite_data_t pnlite_g_data;

static NSDictionary *notificationNameMap;

static char *pnLiteSessionId[128];
static char *pnLiteSessionStartDate[128];
static NSUInteger pnLiteHandledCount;
static bool pnLiteHasRecordedSessions;

/**
 *  Handler executed when the application crashes. Writes information about the
 *  current application state using the crash report writer.
 *
 *  @param writer report writer which will receive updated metadata
 */
void BSSerializeDataCrashHandler(const PNLite_KSCrashReportWriter *writer) {
    if (pnlite_g_data.configJSON) {
        writer->addJSONElement(writer, "config", pnlite_g_data.configJSON);
    }
    if (pnlite_g_data.metaDataJSON) {
        writer->addJSONElement(writer, "metaData",
                               pnlite_g_data.metaDataJSON);
    }

    if (pnLiteHasRecordedSessions) { // a session is available
        // persist session info
        writer->addStringElement(writer, "id", (const char *) pnLiteSessionId);
        writer->addStringElement(writer, "startedAt", (const char *) pnLiteSessionStartDate);
        writer->addUIntegerElement(writer, "handledCount", pnLiteHandledCount);

        if (!pnlite_g_data.handledState) {
            writer->addUIntegerElement(writer, "unhandledCount", 1);
        } else {
            writer->addUIntegerElement(writer, "unhandledCount", 0);
        }
    }

    if (pnlite_g_data.handledState) {
        writer->addJSONElement(writer, "handledState",
                               pnlite_g_data.handledState);
    }

    if (pnlite_g_data.stateJSON) {
        writer->addJSONElement(writer, "state", pnlite_g_data.stateJSON);
    }
    if (pnlite_g_data.userOverridesJSON) {
        writer->addJSONElement(writer, "overrides",
                               pnlite_g_data.userOverridesJSON);
    }
    if (pnlite_g_data.onCrash) {
        pnlite_g_data.onCrash(writer);
    }
}

NSString *PNLiteBreadcrumbNameForNotificationName(NSString *name) {
    NSString *readableName = notificationNameMap[name];

    if (readableName) {
        return readableName;
    } else {
        return [name stringByReplacingOccurrencesOfString:@"Notification"
                                               withString:@""];
    }
}

/**
 *  Writes a dictionary to a destination using the PNLite_KSCrash JSON encoding
 *
 *  @param dictionary  data to encode
 *  @param destination target location of the data
 */
void BSSerializeJSONDictionary(NSDictionary *dictionary, char **destination) {
    if (![NSJSONSerialization isValidJSONObject:dictionary]) {
        pnlite_log_err(@"could not serialize metadata: is not valid JSON object");
        return;
    }
    @try {
        NSError *error;
        NSData *json = [NSJSONSerialization dataWithJSONObject:dictionary
                                                       options:0
                                                         error:&error];

        if (!json) {
            pnlite_log_err(@"could not serialize metaData: %@", error);
            return;
        }
        *destination = reallocf(*destination, [json length] + 1);
        if (*destination) {
            memcpy(*destination, [json bytes], [json length]);
            (*destination)[[json length]] = '\0';
        }
    } @catch (NSException *exception) {
        pnlite_log_err(@"could not serialize metaData: %@", exception);
    }
}

@interface PNLiteNotifier ()
@property(nonatomic) PNLiteCrashSentry *crashSentry;
@property(nonatomic) PNLiteErrorReportApiClient *errorReportApiClient;
@property(nonatomic) PNLiteSessionTrackingApiClient *sessionTrackingApiClient;
@property(nonatomic) PNLiteSessionTracker *sessionTracker;
@property(nonatomic) NSTimer *sessionTimer;
@end

@implementation PNLiteNotifier

@synthesize configuration;

- (id)initWithConfiguration:(PNLiteConfiguration *)initConfiguration {
    if ((self = [super init])) {
        self.configuration = initConfiguration;
        self.state = [[PNLiteMetaData alloc] init];
        self.details = [@{
            PNLiteKeyName : @"Bugsnag Objective-C",
            PNLiteKeyVersion : PNLITE_NOTIFIER_VERSION,
            PNLiteKeyUrl : PNLITE_NOTIFIER_URL
        } mutableCopy];

        self.metaDataLock = [[NSLock alloc] init];
        self.configuration.metaData.delegate = self;
        self.configuration.config.delegate = self;
        self.state.delegate = self;
        self.crashSentry = [PNLiteCrashSentry new];
        self.errorReportApiClient = [[PNLiteErrorReportApiClient alloc] initWithConfig:configuration
                                                                              queueName:@"Error API queue"];
        self.sessionTrackingApiClient = [[PNLiteSessionTrackingApiClient alloc] initWithConfig:configuration
                                                                                      queueName:@"Session API queue"];

        self.sessionTracker = [[PNLiteSessionTracker alloc] initWithConfig:initConfiguration
                                                                  apiClient:self.sessionTrackingApiClient
                                                                   callback:^(PNLiteSession *session) {

                                                                       // copy session id
                                                                       const char *newSessionId = [session.sessionId UTF8String];
                                                                       size_t idSize = strlen(newSessionId);
                                                                       strncpy((char *)pnLiteSessionId, newSessionId, idSize);
                                                                       pnLiteSessionId[idSize - 1] = NULL;

                                                                       const char *newSessionDate = [[PNLite_RFC3339DateTool stringFromDate:session.startedAt] UTF8String];
                                                                       size_t dateSize = strlen(newSessionDate);
                                                                       strncpy((char *)pnLiteSessionStartDate, newSessionDate, dateSize);
                                                                       pnLiteSessionStartDate[dateSize - 1] = NULL;

                                                                       // record info for C JSON serialiser
                                                                       pnLiteHandledCount = session.handledCount;
                                                                       pnLiteHasRecordedSessions = true;
                                                                   }];

        
        [self.sessionTracker startNewSession:[NSDate date] withUser:nil autoCaptured:YES];

        [self metaDataChanged:self.configuration.metaData];
        [self metaDataChanged:self.configuration.config];
        [self metaDataChanged:self.state];
        pnlite_g_data.onCrash = (void (*)(
            const PNLite_KSCrashReportWriter *))self.configuration.onCrashHandler;

        static dispatch_once_t once_t;
        dispatch_once(&once_t, ^{
          [self initializeNotificationNameMap];
        });
    }
    return self;
}

NSString *const kPNLiteWindowVisible = @"Window Became Visible";
NSString *const kPNLiteWindowHidden = @"Window Became Hidden";
NSString *const kPNLiteBeganTextEdit = @"Began Editing Text";
NSString *const kPNLiteStoppedTextEdit = @"Stopped Editing Text";
NSString *const kPNLiteUndoOperation = @"Undo Operation";
NSString *const kPNLiteRedoOperation = @"Redo Operation";
NSString *const kPNLiteTableViewSelectionChange = @"TableView Select Change";
NSString *const kPNLiteAppWillTerminate = @"App Will Terminate";

- (void)initializeNotificationNameMap {
    notificationNameMap = @{
#if TARGET_OS_TV
        NSUndoManagerDidUndoChangeNotification : kUndoOperation,
        NSUndoManagerDidRedoChangeNotification : kRedoOperation,
        UIWindowDidBecomeVisibleNotification : kWindowVisible,
        UIWindowDidBecomeHiddenNotification : kWindowHidden,
        UIWindowDidBecomeKeyNotification : @"Window Became Key",
        UIWindowDidResignKeyNotification : @"Window Resigned Key",
        UIScreenBrightnessDidChangeNotification : @"Screen Brightness Changed",
        UITableViewSelectionDidChangeNotification : kTableViewSelectionChange,

#elif TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
        UIWindowDidBecomeVisibleNotification : kPNLiteWindowVisible,
        UIWindowDidBecomeHiddenNotification : kPNLiteWindowHidden,
        UIApplicationWillTerminateNotification : kPNLiteAppWillTerminate,
        UIApplicationWillEnterForegroundNotification :
            @"App Will Enter Foreground",
        UIApplicationDidEnterBackgroundNotification :
            @"App Did Enter Background",
        UIKeyboardDidShowNotification : @"Keyboard Became Visible",
        UIKeyboardDidHideNotification : @"Keyboard Became Hidden",
        UIMenuControllerDidShowMenuNotification : @"Did Show Menu",
        UIMenuControllerDidHideMenuNotification : @"Did Hide Menu",
        NSUndoManagerDidUndoChangeNotification : kPNLiteUndoOperation,
        NSUndoManagerDidRedoChangeNotification : kPNLiteRedoOperation,
        UIApplicationUserDidTakeScreenshotNotification : @"Took Screenshot",
        UITextFieldTextDidBeginEditingNotification : kPNLiteBeganTextEdit,
        UITextViewTextDidBeginEditingNotification : kPNLiteBeganTextEdit,
        UITextFieldTextDidEndEditingNotification : kPNLiteStoppedTextEdit,
        UITextViewTextDidEndEditingNotification : kPNLiteStoppedTextEdit,
        UITableViewSelectionDidChangeNotification : kPNLiteTableViewSelectionChange,
        UIDeviceBatteryStateDidChangeNotification : @"Battery State Changed",
        UIDeviceBatteryLevelDidChangeNotification : @"Battery Level Changed",
        UIDeviceOrientationDidChangeNotification : @"Orientation Changed",
        UIApplicationDidReceiveMemoryWarningNotification : @"Memory Warning",

#elif TARGET_OS_MAC
        NSApplicationDidBecomeActiveNotification : @"App Became Active",
        NSApplicationDidResignActiveNotification : @"App Resigned Active",
        NSApplicationDidHideNotification : @"App Did Hide",
        NSApplicationDidUnhideNotification : @"App Did Unhide",
        NSApplicationWillTerminateNotification : kAppWillTerminate,
        NSWorkspaceScreensDidSleepNotification : @"Workspace Screen Slept",
        NSWorkspaceScreensDidWakeNotification : @"Workspace Screen Awoke",
        NSWindowWillCloseNotification : @"Window Will Close",
        NSWindowDidBecomeKeyNotification : @"Window Became Key",
        NSWindowWillMiniaturizeNotification : @"Window Will Miniaturize",
        NSWindowDidEnterFullScreenNotification : @"Window Entered Full Screen",
        NSWindowDidExitFullScreenNotification : @"Window Exited Full Screen",
        NSControlTextDidBeginEditingNotification : @"Control Text Began Edit",
        NSControlTextDidEndEditingNotification : @"Control Text Ended Edit",
        NSMenuWillSendActionNotification : @"Menu Will Send Action",
        NSTableViewSelectionDidChangeNotification : kTableViewSelectionChange,
#endif
    };
}

- (void)start {
    [self.crashSentry install:self.configuration
                    apiClient:self.errorReportApiClient
                      onCrash:&BSSerializeDataCrashHandler];

    [self setupConnectivityListener];
    [self updateAutomaticBreadcrumbDetectionSettings];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [self watchLifecycleEvents:center];

#if TARGET_OS_TV
    [self.details setValue:@"tvOS Bugsnag Notifier" forKey:PNLiteKeyName];

#elif TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    [self.details setValue:@"iOS Bugsnag Notifier" forKey:PNLiteKeyName];

    [center addObserver:self
               selector:@selector(batteryChanged:)
                   name:UIDeviceBatteryStateDidChangeNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(batteryChanged:)
                   name:UIDeviceBatteryLevelDidChangeNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(orientationChanged:)
                   name:UIDeviceOrientationDidChangeNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(lowMemoryWarning:)
                   name:UIApplicationDidReceiveMemoryWarningNotification
                 object:nil];

    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];

    [self batteryChanged:nil];
    [self orientationChanged:nil];
#elif TARGET_OS_MAC
    [self.details setValue:@"OSX Bugsnag Notifier" forKey:PNLiteKeyName];

    [center addObserver:self
               selector:@selector(willEnterForeground:)
                   name:NSApplicationDidBecomeActiveNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(willEnterBackground:)
                   name:NSApplicationDidResignActiveNotification
                 object:nil];
#endif

    // notification not received in time on initial startup, so trigger manually
    [self willEnterForeground:self];
}

- (void)watchLifecycleEvents:(NSNotificationCenter *)center {
    NSString *foregroundName;
    NSString *backgroundName;
    
    #if TARGET_OS_TV || TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    foregroundName = UIApplicationWillEnterForegroundNotification;
    backgroundName = UIApplicationWillEnterForegroundNotification;
    #elif TARGET_OS_MAC
    foregroundName = NSApplicationWillBecomeActiveNotification;
    backgroundName = NSApplicationDidFinishLaunchingNotification;
    #endif
    
    [center addObserver:self
               selector:@selector(willEnterForeground:)
                   name:foregroundName
                 object:nil];

    [center addObserver:self
               selector:@selector(willEnterBackground:)
                   name:backgroundName
                 object:nil];
}

- (void)willEnterForeground:(id)sender {
    [self.sessionTracker startNewSession:[NSDate date]
                                withUser:self.configuration.currentUser
                            autoCaptured:YES];

    NSTimeInterval sessionTickSeconds = 60;

    if (!self.sessionTimer) {
        _sessionTimer = [NSTimer scheduledTimerWithTimeInterval:sessionTickSeconds
                                                         target:self
                                                       selector:@selector(sessionTick:)
                                                       userInfo:nil
                                                        repeats:YES];
        [self sessionTick:self];
    }
}

- (void)willEnterBackground:(id)sender {
    [self.sessionTracker suspendCurrentSession:[NSDate date]];

    if (self.sessionTimer) {
        [self.sessionTimer invalidate];
        self.sessionTimer = nil;
    }

}

- (void)sessionTick:(id)sender {
    [self.sessionTracker send];
}

- (void)flushPendingReports {
    [self.errorReportApiClient flushPendingData];
}

- (void)setupConnectivityListener {
    NSURL *url = self.configuration.notifyURL;

    __weak id weakSelf = self;
    self.networkReachable =
        [[PNLiteConnectivity alloc] initWithURL:url
                                 changeBlock:^(PNLiteConnectivity *connectivity) {
                                   [weakSelf flushPendingReports];
                                 }];
    [self.networkReachable startWatchingConnectivity];
}

- (void)startSession {
    [self.sessionTracker startNewSession:[NSDate date]
                                withUser:self.configuration.currentUser
                            autoCaptured:NO];
}

- (void)notifyError:(NSError *)error
              block:(void (^)(PNLiteCrashReport *))block {
    PNLiteHandledState *state =
        [PNLiteHandledState handledStateWithSeverityReason:PNLite_HandledError
                                                   severity:PNLiteSeverityWarning
                                                  attrValue:error.domain];
    [self notify:NSStringFromClass([error class])
             message:error.localizedDescription
        handledState:state
               block:^(PNLiteCrashReport *_Nonnull report) {
                 NSMutableDictionary *metadata = [report.metaData mutableCopy];
                 metadata[@"nserror"] = @{
                     @"code" : @(error.code),
                     @"domain" : error.domain,
                     PNLiteKeyReason : error.localizedFailureReason ?: @""
                 };
                   if (report.context == nil) { // set context as error domain
                       report.context = [NSString stringWithFormat:@"%@ (%ld)", error.domain, (long)error.code];
                   }
                 report.metaData = metadata;

                 if (block) {
                     block(report);
                 }
               }];
}

- (void)notifyException:(NSException *)exception
             atSeverity:(PNLiteSeverity)severity
                  block:(void (^)(PNLiteCrashReport *))block {

    PNLiteHandledState *state = [PNLiteHandledState
        handledStateWithSeverityReason:PNLite_UserSpecifiedSeverity
                              severity:severity
                             attrValue:nil];
    [self notify:exception.name ?: NSStringFromClass([exception class])
             message:exception.reason
        handledState:state
               block:block];
}

- (void)notifyException:(NSException *)exception
                  block:(void (^)(PNLiteCrashReport *))block {
    PNLiteHandledState *state =
        [PNLiteHandledState handledStateWithSeverityReason:PNLite_HandledException];
    [self notify:exception.name ?: NSStringFromClass([exception class])
             message:exception.reason
        handledState:state
               block:block];
}

- (void)internalClientNotify:(NSException *_Nonnull)exception
                    withData:(NSDictionary *_Nullable)metaData
                       block:(PNLiteNotifyBlock _Nullable)block {

    NSString *severity = metaData[PNLiteKeySeverity];
    NSString *severityReason = metaData[PNLiteKeySeverityReason];
    NSString *logLevel = metaData[PNLiteKeyLogLevel];
    NSParameterAssert(severity.length > 0);
    NSParameterAssert(severityReason.length > 0);

    PNLiteSeverityReasonType severityReasonType =
        [PNLiteHandledState severityReasonFromString:severityReason];

    PNLiteHandledState *state = [PNLiteHandledState
        handledStateWithSeverityReason:severityReasonType
                              severity:PNLiteParseSeverity(severity)
                             attrValue:logLevel];

    [self notify:exception.name ?: NSStringFromClass([exception class])
             message:exception.reason
        handledState:state
               block:^(PNLiteCrashReport *_Nonnull report) {
                 if (block) {
                     block(report);
                 }
               }];
}

- (void)notify:(NSString *)exceptionName
         message:(NSString *)message
    handledState:(PNLiteHandledState *_Nonnull)handledState
           block:(void (^)(PNLiteCrashReport *))block {

    [self.sessionTracker incrementHandledError];

    PNLiteCrashReport *report = [[PNLiteCrashReport alloc]
        initWithErrorName:exceptionName
             errorMessage:message
            configuration:self.configuration
                 metaData:[self.configuration.metaData toDictionary]
             handledState:handledState
                  session:self.sessionTracker.currentSession];
    if (block) {
        block(report);
    }

    [self.metaDataLock lock];
    BSSerializeJSONDictionary([report.handledState toJson],
                              &pnlite_g_data.handledState);
    BSSerializeJSONDictionary(report.metaData,
                              &pnlite_g_data.metaDataJSON);
    BSSerializeJSONDictionary(report.overrides,
                              &pnlite_g_data.userOverridesJSON);

    [self.state addAttribute:PNLiteKeySeverity
                   withValue:PNLiteFormatSeverity(report.severity)
               toTabWithName:PNLITE_BSTabCrash];

    //    We discard 5 stack frames (including this one) by default,
    //    and sum that with the number specified by report.depth:
    //
    //    0 pnlite_kscrashsentry_reportUserException
    //    1 pnlite_kscrash_reportUserException
    //    2 -[PNLite_KSCrash
    //    reportUserException:reason:language:lineOfCode:stackTrace:terminateProgram:]
    //    3 -[PNLiteCrashSentry reportUserException:reason:]
    //    4 -[PNLiteNotifier notify:message:block:]

    NSNumber *depth = @(PNLITE_NotifierStackFrameCount + report.depth);
    [self.state addAttribute:PNLITE_BSAttributeDepth
                   withValue:depth
               toTabWithName:PNLITE_BSTabCrash];

    NSString *reportName =
        report.errorClass ?: NSStringFromClass([NSException class]);
    NSString *reportMessage = report.errorMessage ?: @"";

    [self.crashSentry reportUserException:reportName reason:reportMessage];
    pnlite_g_data.userOverridesJSON = NULL;
    pnlite_g_data.handledState = NULL;

    // Restore metaData to pre-crash state.
    [self.metaDataLock unlock];
    [self metaDataChanged:self.configuration.metaData];
    [[self state] clearTab:PNLITE_BSTabCrash];
    [self addBreadcrumbWithBlock:^(PNLiteBreadcrumb *_Nonnull crumb) {
        crumb.type = PNLiteBreadcrumbTypeError;
      crumb.name = reportName;
      crumb.metadata = @{
          PNLiteKeyMessage : reportMessage,
          PNLiteKeySeverity : PNLiteFormatSeverity(report.severity)
      };
    }];
    [self flushPendingReports];
}

- (void)addBreadcrumbWithBlock:
    (void (^_Nonnull)(PNLiteBreadcrumb *_Nonnull))block {
    [self.configuration.breadcrumbs addBreadcrumbWithBlock:block];
    [self serializeBreadcrumbs];
}

- (void)clearBreadcrumbs {
    [self.configuration.breadcrumbs clearBreadcrumbs];
    [self serializeBreadcrumbs];
}

- (void)serializeBreadcrumbs {
    PNLiteBreadcrumbs *crumbs = self.configuration.breadcrumbs;
    NSArray *arrayValue = crumbs.count == 0 ? nil : [crumbs arrayValue];
    [self.state addAttribute:PNLiteKeyBreadcrumbs
                   withValue:arrayValue
               toTabWithName:PNLITE_BSTabCrash];
}

- (void)metaDataChanged:(PNLiteMetaData *)metaData {
    @synchronized(metaData) {
        if (metaData == self.configuration.metaData) {
            if ([self.metaDataLock tryLock]) {
                BSSerializeJSONDictionary([metaData toDictionary],
                                          &pnlite_g_data.metaDataJSON);
                [self.metaDataLock unlock];
            }
        } else if (metaData == self.configuration.config) {
            BSSerializeJSONDictionary([metaData getTab:PNLiteKeyConfig],
                                      &pnlite_g_data.configJSON);
        } else if (metaData == self.state) {
            BSSerializeJSONDictionary([metaData toDictionary],
                                      &pnlite_g_data.stateJSON);
        } else {
            pnlite_log_debug(@"Unknown metadata dictionary changed");
        }
    }
}

#if TARGET_OS_TV
#elif TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
- (void)batteryChanged:(NSNotification *)notif {
    NSNumber *batteryLevel =
            @([UIDevice currentDevice].batteryLevel);
    NSNumber *charging =
            @([UIDevice currentDevice].batteryState ==
                    UIDeviceBatteryStateCharging);

    [[self state] addAttribute:PNLiteKeyBatteryLevel
                     withValue:batteryLevel
                 toTabWithName:PNLiteKeyDeviceState];
    [[self state] addAttribute:PNLiteKeyCharging
                     withValue:charging
                 toTabWithName:PNLiteKeyDeviceState];
}

- (void)orientationChanged:(NSNotification *)notif {
    NSString *orientation;
    UIDeviceOrientation deviceOrientation =
        [UIDevice currentDevice].orientation;

    switch (deviceOrientation) {
    case UIDeviceOrientationPortraitUpsideDown:
        orientation = @"portraitupsidedown";
        break;
    case UIDeviceOrientationPortrait:
        orientation = @"portrait";
        break;
    case UIDeviceOrientationLandscapeRight:
        orientation = @"landscaperight";
        break;
    case UIDeviceOrientationLandscapeLeft:
        orientation = @"landscapeleft";
        break;
    case UIDeviceOrientationFaceUp:
        orientation = @"faceup";
        break;
    case UIDeviceOrientationFaceDown:
        orientation = @"facedown";
        break;
    default:
        return; // always ignore unknown breadcrumbs
    }

    NSDictionary *lastBreadcrumb =
        [[self.configuration.breadcrumbs arrayValue] lastObject];
    NSString *orientationNotifName =
        PNLiteBreadcrumbNameForNotificationName(notif.name);

    if (lastBreadcrumb &&
        [orientationNotifName isEqualToString:lastBreadcrumb[PNLiteKeyName]]) {
        NSDictionary *metaData = lastBreadcrumb[PNLiteKeyMetaData];

        if ([orientation isEqualToString:metaData[PNLiteKeyOrientation]]) {
            return; // ignore duplicate orientation event
        }
    }

    [[self state] addAttribute:PNLiteKeyOrientation
                     withValue:orientation
                 toTabWithName:PNLiteKeyDeviceState];
    if ([self.configuration automaticallyCollectBreadcrumbs]) {
        [self addBreadcrumbWithBlock:^(PNLiteBreadcrumb *_Nonnull breadcrumb) {
          breadcrumb.type = PNLiteBreadcrumbTypeState;
          breadcrumb.name = orientationNotifName;
          breadcrumb.metadata = @{PNLiteKeyOrientation : orientation};
        }];
    }
}

- (void)lowMemoryWarning:(NSNotification *)notif {
    [[self state] addAttribute:PNLITE_BSEventLowMemoryWarning
                     withValue:[[PNLiteCrashTracker payloadDateFormatter]
                                   stringFromDate:[NSDate date]]
                 toTabWithName:PNLiteKeyDeviceState];
    if ([self.configuration automaticallyCollectBreadcrumbs]) {
        [self sendBreadcrumbForNotification:notif];
    }
}
#endif

- (void)updateAutomaticBreadcrumbDetectionSettings {
    if ([self.configuration automaticallyCollectBreadcrumbs]) {
        for (NSString *name in [self automaticBreadcrumbStateEvents]) {
            [self crumbleNotification:name];
        }
        for (NSString *name in [self automaticBreadcrumbTableItemEvents]) {
            [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(sendBreadcrumbForTableViewNotification:)
                       name:name
                     object:nil];
        }
        for (NSString *name in [self automaticBreadcrumbControlEvents]) {
            [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(sendBreadcrumbForControlNotification:)
                       name:name
                     object:nil];
        }
        for (NSString *name in [self automaticBreadcrumbMenuItemEvents]) {
            [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(sendBreadcrumbForMenuItemNotification:)
                       name:name
                     object:nil];
        }
    } else {
        NSArray *eventNames = [[[[self automaticBreadcrumbStateEvents]
            arrayByAddingObjectsFromArray:[self
                                              automaticBreadcrumbControlEvents]]
            arrayByAddingObjectsFromArray:
                [self automaticBreadcrumbMenuItemEvents]]
            arrayByAddingObjectsFromArray:
                [self automaticBreadcrumbTableItemEvents]];
        for (NSString *name in eventNames) {
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:name
                                                          object:nil];
        }
    }
}

- (NSArray<NSString *> *)automaticBreadcrumbStateEvents {
#if TARGET_OS_TV
    return @[
        NSUndoManagerDidUndoChangeNotification,
        NSUndoManagerDidRedoChangeNotification,
        UIWindowDidBecomeVisibleNotification,
        UIWindowDidBecomeHiddenNotification, UIWindowDidBecomeKeyNotification,
        UIWindowDidResignKeyNotification,
        UIScreenBrightnessDidChangeNotification
    ];
#elif TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    return @[
        UIWindowDidBecomeHiddenNotification,
        UIWindowDidBecomeVisibleNotification,
        UIApplicationWillTerminateNotification,
        UIApplicationWillEnterForegroundNotification,
        UIApplicationDidEnterBackgroundNotification,
        UIKeyboardDidShowNotification, UIKeyboardDidHideNotification,
        UIMenuControllerDidShowMenuNotification,
        UIMenuControllerDidHideMenuNotification,
        NSUndoManagerDidUndoChangeNotification,
        NSUndoManagerDidRedoChangeNotification,
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_7_0
        UIApplicationUserDidTakeScreenshotNotification
#endif
    ];
#elif TARGET_OS_MAC
    return @[
        NSApplicationDidBecomeActiveNotification,
        NSApplicationDidResignActiveNotification,
        NSApplicationDidHideNotification, NSApplicationDidUnhideNotification,
        NSApplicationWillTerminateNotification,
        NSWorkspaceScreensDidSleepNotification,
        NSWorkspaceScreensDidWakeNotification, NSWindowWillCloseNotification,
        NSWindowDidBecomeKeyNotification, NSWindowWillMiniaturizeNotification,
        NSWindowDidEnterFullScreenNotification,
        NSWindowDidExitFullScreenNotification
    ];
#else
    return nil;
#endif
}

- (NSArray<NSString *> *)automaticBreadcrumbControlEvents {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    return @[
        UITextFieldTextDidBeginEditingNotification,
        UITextViewTextDidBeginEditingNotification,
        UITextFieldTextDidEndEditingNotification,
        UITextViewTextDidEndEditingNotification
    ];
#elif TARGET_OS_MAC
    return @[
        NSControlTextDidBeginEditingNotification,
        NSControlTextDidEndEditingNotification
    ];
#else
    return nil;
#endif
}

- (NSArray<NSString *> *)automaticBreadcrumbTableItemEvents {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE || TARGET_OS_TV
    return @[ UITableViewSelectionDidChangeNotification ];
#elif TARGET_OS_MAC
    return @[ NSTableViewSelectionDidChangeNotification ];
#else
    return nil;
#endif
}

- (NSArray<NSString *> *)automaticBreadcrumbMenuItemEvents {
#if TARGET_OS_TV
    return @[];
#elif TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    return nil;
#elif TARGET_OS_MAC
    return @[ NSMenuWillSendActionNotification ];
#else
    return nil;
#endif
}

- (void)crumbleNotification:(NSString *)notificationName {
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(sendBreadcrumbForNotification:)
               name:notificationName
             object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)sendBreadcrumbForNotification:(NSNotification *)note {
    [self addBreadcrumbWithBlock:^(PNLiteBreadcrumb *_Nonnull breadcrumb) {
      breadcrumb.type = PNLiteBreadcrumbTypeState;
      breadcrumb.name = PNLiteBreadcrumbNameForNotificationName(note.name);
    }];
}

- (void)sendBreadcrumbForTableViewNotification:(NSNotification *)note {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE || TARGET_OS_TV
    UITableView *tableView = [note object];
    NSIndexPath *indexPath = [tableView indexPathForSelectedRow];
    [self addBreadcrumbWithBlock:^(PNLiteBreadcrumb *_Nonnull breadcrumb) {
      breadcrumb.type = PNLiteBreadcrumbTypeNavigation;
      breadcrumb.name = PNLiteBreadcrumbNameForNotificationName(note.name);
      if (indexPath) {
          breadcrumb.metadata =
              @{ @"row" : @(indexPath.row),
                 @"section" : @(indexPath.section) };
      }
    }];
#elif TARGET_OS_MAC
    NSTableView *tableView = [note object];
    [self addBreadcrumbWithBlock:^(PNLiteBreadcrumb *_Nonnull breadcrumb) {
      breadcrumb.type = PNLiteBreadcrumbTypeNavigation;
      breadcrumb.name = PNLiteBreadcrumbNameForNotificationName(note.name);
      if (tableView) {
          breadcrumb.metadata = @{
              @"selectedRow" : @(tableView.selectedRow),
              @"selectedColumn" : @(tableView.selectedColumn)
          };
      }
    }];
#endif
}

- (void)sendBreadcrumbForMenuItemNotification:(NSNotification *)notif {
#if TARGET_OS_TV
#elif TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
#elif TARGET_OS_MAC
    NSMenuItem *menuItem = [[notif userInfo] valueForKey:@"MenuItem"];
    if ([menuItem isKindOfClass:[NSMenuItem class]]) {
        [self addBreadcrumbWithBlock:^(PNLiteBreadcrumb *_Nonnull breadcrumb) {
          breadcrumb.type = PNLiteBreadcrumbTypeState;
          breadcrumb.name = PNLiteBreadcrumbNameForNotificationName(notif.name);
          if (menuItem.title.length > 0)
              breadcrumb.metadata = @{PNLiteKeyAction : menuItem.title};
        }];
    }
#endif
}

- (void)sendBreadcrumbForControlNotification:(NSNotification *)note {
#if TARGET_OS_TV
#elif TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    UIControl *control = note.object;
    [self addBreadcrumbWithBlock:^(PNLiteBreadcrumb *_Nonnull breadcrumb) {
      breadcrumb.type = PNLiteBreadcrumbTypeUser;
      breadcrumb.name = PNLiteBreadcrumbNameForNotificationName(note.name);
      NSString *label = control.accessibilityLabel;
      if (label.length > 0) {
          breadcrumb.metadata = @{PNLiteKeyLabel : label};
      }
    }];
#elif TARGET_OS_MAC
    NSControl *control = note.object;
    [self addBreadcrumbWithBlock:^(PNLiteBreadcrumb *_Nonnull breadcrumb) {
      breadcrumb.type = PNLiteBreadcrumbTypeUser;
      breadcrumb.name = PNLiteBreadcrumbNameForNotificationName(note.name);
      if ([control respondsToSelector:@selector(accessibilityLabel)]) {
          NSString *label = control.accessibilityLabel;
          if (label.length > 0) {
              breadcrumb.metadata = @{PNLiteKeyLabel : label};
          }
      }
    }];
#endif
}

@end
