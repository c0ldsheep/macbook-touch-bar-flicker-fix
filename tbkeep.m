// tbkeep: stops the white flashes and flicker on a MacBook Pro Touch Bar whose screen flickers
// at low brightness. https://github.com/c0ldsheep/macbook-touch-bar-flicker-fix
//
// What it does
//   1. Holds the Touch Bar at a fixed brightness (default 60%, about 219 nits). Auto-brightness is
//      switched off for the Touch Bar only. The main screen is a different display and is never touched.
//   2. When you stop typing, macOS dims the Touch Bar to about 15% of its level for 15 seconds before
//      switching it off. That dim stage is in the flicker range, so tbkeep switches the bar off right away.
//      Any key or trackpad touch wakes it as usual.
//
// It only talks to Apple's own brightness services (the private CoreBrightness and DFRBrightness
// frameworks). No admin rights, no network, no files touched except its settings and its log.
// If a future macOS removes those services, tbkeep stops itself and the Touch Bar keeps Apple's
// normal behaviour.
//
// Commands
//   tbkeep              show status
//   tbkeep 70           set the level to 70% (5-100) and apply it now
//   tbkeep try          step through levels to find the lowest one with no flicker
//   tbkeep dim on|off   on (default): skip macOS's dim stage; off: keep it
//   tbkeep auto         pause the fix and give the Touch Bar back to macOS
//   tbkeep uninstall    remove tbkeep completely
//   tbkeep run          background mode (started at login by ~/Library/LaunchAgents/local.tbkeep.plist)
//
// Build: clang -fobjc-arc -O2 -framework Foundation -framework AppKit tbkeep.m -o tbkeep

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <ctype.h>
#import <dlfcn.h>
#import <math.h>
#import <sys/sysctl.h>

#define TBKEEP_VERSION "1.1.0"

@interface BrightnessSystemClient : NSObject
- (id)copyPropertyForKey:(id)key;
- (id)copyPropertyForKey:(id)key andDisplay:(unsigned long long)display;
- (BOOL)setProperty:(id)value withKey:(id)key andDisplay:(unsigned long long)display;
@end

@interface DFRBrightnessClient : NSObject
- (int)getDFRDisplayID;
- (long long)getDimmingStep;
- (BOOL)dimToStep:(long long)step withPeriod:(float)period;
@end

static NSString *const kAgentLabel = @"local.tbkeep";
static const int kTypeTouchBar = 3;        // CoreBrightness display type of the Touch Bar (the main screen is 0)
static const long long kStepDim = 2;       // Touch Bar dimming steps: 1 normal, 2 dim (~15%), 4 off
static const long long kStepOff = 4;
static const double kDefaultLevel = 0.60;  // about 219 nits

#pragma mark - Settings and log

// Settings live in ~/Library/Application Support/tbkeep (TBKEEP_DIR overrides it for testing).
static NSString *SupportDir(void) {
  NSString *custom = NSProcessInfo.processInfo.environment[@"TBKEEP_DIR"];
  if (custom.length) return custom;
  return [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/tbkeep"];
}

static NSString *ReadSetting(NSString *name) {
  NSString *path = [SupportDir() stringByAppendingPathComponent:name];
  NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
  return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static BOOL WriteSetting(NSString *name, NSString *value) {
  [NSFileManager.defaultManager createDirectoryAtPath:SupportDir() withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *path = [SupportDir() stringByAppendingPathComponent:name];
  return [[value stringByAppendingString:@"\n"] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// The saved level (0.05-1.0), or NAN when the fix is paused ("auto").
static double SavedLevel(void) {
  NSString *text = ReadSetting(@"level");
  if (text.length == 0) return kDefaultLevel;
  if ([text isEqualToString:@"auto"]) return NAN;
  double level = text.doubleValue;
  return (level >= 0.05 && level <= 1.0) ? level : kDefaultLevel;
}

static BOOL SkipDimStage(void) { return ![ReadSetting(@"dim") isEqualToString:@"keep"]; }

// Writes one line to the log (stderr, which launchd sends to ~/Library/Logs/tbkeep.log).
// At most 60 lines an hour, so a misbehaving system can never fill the disk.
static void Log(NSString *format, ...) {
  static NSDate *hourStart;
  static int linesThisHour;
  NSDate *now = NSDate.date;
  if (!hourStart || [now timeIntervalSinceDate:hourStart] > 3600) {
    hourStart = now;
    linesThisHour = 0;
  }
  if (++linesThisHour > 60) return;
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  NSDateFormatter *formatter = [NSDateFormatter new];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
  fprintf(stderr, "%s %s\n", [formatter stringFromDate:now].UTF8String, message.UTF8String);
  fflush(stderr);
}

#pragma mark - Apple's brightness services

static BOOL OpenFramework(NSString *name) {
  NSString *base = [NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework", name];
  return dlopen([base stringByAppendingFormat:@"/Versions/A/%@", name].UTF8String, RTLD_NOW) ||
         dlopen([base stringByAppendingFormat:@"/%@", name].UTF8String, RTLD_NOW);
}

// nil when everything tbkeep needs is present; otherwise the reason it can't work.
static NSString *MissingAPI(void) {
  if (!OpenFramework(@"CoreBrightness")) return @"Apple's CoreBrightness framework was not found";
  if (!OpenFramework(@"DFRBrightness")) return @"Apple's Touch Bar brightness framework was not found";
  Class brightness = NSClassFromString(@"BrightnessSystemClient");
  Class dimming = NSClassFromString(@"DFRBrightnessClient");
  if (!brightness || !dimming) return @"Apple's brightness classes were not found";
  for (NSString *selector in @[ @"copyPropertyForKey:", @"copyPropertyForKey:andDisplay:", @"setProperty:withKey:andDisplay:" ])
    if (![brightness instancesRespondToSelector:NSSelectorFromString(selector)])
      return [NSString stringWithFormat:@"BrightnessSystemClient has no %@", selector];
  for (NSString *selector in @[ @"getDimmingStep", @"dimToStep:withPeriod:" ])
    if (![dimming instancesRespondToSelector:NSSelectorFromString(selector)])
      return [NSString stringWithFormat:@"DFRBrightnessClient has no %@", selector];
  return nil;
}

static BOOL ReportsTouchBarType(BrightnessSystemClient *brightness, long long display, BOOL requireType) {
  id type = [brightness copyPropertyForKey:@"CBDisplayType" andDisplay:display];
  if (![type isKindOfClass:NSNumber.class]) return !requireType;
  return [type intValue] == kTypeTouchBar;
}

// Which display is the Touch Bar, or -1. Asks Apple's own Touch Bar client first and never accepts
// a display that reports another type, so the main screen can't be changed by mistake.
static long long TouchBarDisplay(BrightnessSystemClient *brightness, DFRBrightnessClient *dimming) {
  if (!brightness) return -1;
  if ([dimming respondsToSelector:@selector(getDFRDisplayID)]) {
    int display = [dimming getDFRDisplayID];
    if (display > 0 && ReportsTouchBarType(brightness, display, NO)) return display;
  }
  id list = [brightness copyPropertyForKey:@"CBDisplayList"];
  if (![list isKindOfClass:NSDictionary.class]) return -1;
  for (NSNumber *display in list[@"CBDisplayDeviceIDs"])
    if ([display isKindOfClass:NSNumber.class] && ReportsTouchBarType(brightness, display.longLongValue, YES))
      return display.longLongValue;
  return -1;
}

// The Touch Bar's current level (0-1), or NAN if the brightness service did not answer.
static double CurrentLevel(BrightnessSystemClient *brightness, long long display, BOOL *autoOn, double *nits) {
  id autoValue = [brightness copyPropertyForKey:@"DisplayBrightnessAuto" andDisplay:display];
  id value = [brightness copyPropertyForKey:@"DisplayBrightness" andDisplay:display];
  if (autoOn) *autoOn = [autoValue isKindOfClass:NSNumber.class] && [autoValue boolValue];
  if (![value isKindOfClass:NSDictionary.class]) return NAN;
  if (nits) *nits = [value[@"Nits"] doubleValue];
  return [value[@"Brightness"] doubleValue];
}

static BOOL ApplyLevel(BrightnessSystemClient *brightness, long long display, double level) {
  BOOL autoOff = [brightness setProperty:@NO withKey:@"DisplayBrightnessAuto" andDisplay:display];
  BOOL levelSet = [brightness setProperty:@{@"Brightness" : @(level)} withKey:@"DisplayBrightness" andDisplay:display];
  return autoOff && levelSet;
}

static BOOL ApplyAuto(BrightnessSystemClient *brightness, long long display) {
  return [brightness setProperty:@YES withKey:@"DisplayBrightnessAuto" andDisplay:display];
}

#pragma mark - Background mode

@interface Keeper : NSObject
@property(strong) BrightnessSystemClient *brightness;
@property(strong) DFRBrightnessClient *dimming;
@property long long display;
@property double level;
@property BOOL skipDim;
@property NSUInteger ticks;
@property NSUInteger checksWithoutTouchBar;
@end

@implementation Keeper

- (void)connect {
  self.brightness = [[NSClassFromString(@"BrightnessSystemClient") alloc] init];
  self.dimming = [[NSClassFromString(@"DFRBrightnessClient") alloc] init];
}

// Re-reads the settings and puts the Touch Bar back on its level if anything changed it.
- (void)enforce:(NSString *)reason {
  self.level = SavedLevel();
  self.skipDim = SkipDimStage();
  self.display = TouchBarDisplay(self.brightness, self.dimming);
  if (self.display < 0) {  // the brightness service may have restarted
    [self connect];
    self.display = TouchBarDisplay(self.brightness, self.dimming);
  }
  if (self.display < 0) {
    if (++self.checksWithoutTouchBar == 30) Log(@"no Touch Bar display found yet; still checking");
    return;
  }
  self.checksWithoutTouchBar = 0;

  BOOL autoOn = NO;
  double current = CurrentLevel(self.brightness, self.display, &autoOn, NULL);
  if (isnan(self.level)) {
    if (!autoOn && ApplyAuto(self.brightness, self.display)) Log(@"paused: macOS controls the Touch Bar (%@)", reason);
    return;
  }
  if (autoOn || isnan(current) || fabs(current - self.level) > 0.02) {
    BOOL ok = ApplyLevel(self.brightness, self.display, self.level);
    Log(@"level %.0f%% %@ (%@; it was %@)", self.level * 100, ok ? @"applied" : @"FAILED to apply", reason,
        autoOn ? @"on auto" : (isnan(current) ? @"unknown" : [NSString stringWithFormat:@"%.0f%%", current * 100]));
  }
}

// Every 0.5 s: skip macOS's dim stage. Every 2 s: check the level.
- (void)tick {
  if (++self.ticks % 4 == 0) [self enforce:@"check"];
  if (!self.skipDim || isnan(self.level) || self.display < 0 || !self.dimming) return;
  if ([self.dimming getDimmingStep] == kStepDim) [self.dimming dimToStep:kStepOff withPeriod:0.2];
}

@end

static int Run(void) {
  NSString *missing = MissingAPI();
  if (missing) {
    // Exit 0 so launchd does not restart it; the Touch Bar keeps Apple's normal behaviour.
    Log(@"tbkeep %s stopped: %@. The Touch Bar keeps macOS's normal behaviour.", TBKEEP_VERSION, missing);
    return 0;
  }
  Keeper *keeper = [Keeper new];
  [keeper connect];
  [keeper enforce:@"start"];
  Log(@"tbkeep %s running: level %@, dim stage %@", TBKEEP_VERSION,
      isnan(keeper.level) ? @"auto (paused)" : [NSString stringWithFormat:@"%.0f%%", keeper.level * 100],
      keeper.skipDim ? @"skipped" : @"kept");

  NSNotificationCenter *center = NSWorkspace.sharedWorkspace.notificationCenter;
  for (NSString *name in @[ NSWorkspaceDidWakeNotification, NSWorkspaceScreensDidWakeNotification,
                            NSWorkspaceSessionDidBecomeActiveNotification ]) {
    [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
      [keeper enforce:@"wake"];
    }];
  }
  NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [keeper tick]; }];
  timer.tolerance = 0.1;
  [NSRunLoop.mainRunLoop run];
  return 0;
}

#pragma mark - Commands

static NSString *MacModel(void) {
  char model[64] = {0};
  size_t size = sizeof(model);
  sysctlbyname("hw.model", model, &size, NULL, 0);
  return [NSString stringWithFormat:@"%s, macOS %@", model, NSProcessInfo.processInfo.operatingSystemVersionString];
}

static BOOL AgentRunning(void) {
  NSTask *task = [NSTask new];
  task.launchPath = @"/bin/launchctl";
  task.arguments = @[ @"print", [NSString stringWithFormat:@"gui/%d/%@", getuid(), kAgentLabel] ];
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = [NSFileHandle fileHandleWithNullDevice];
  [task launch];
  NSData *output = [pipe.fileHandleForReading readDataToEndOfFile];
  [task waitUntilExit];
  return [[[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] containsString:@"state = running"];
}

static int Status(BrightnessSystemClient *brightness, long long display) {
  BOOL autoOn = NO;
  double nits = 0, saved = SavedLevel();
  CurrentLevel(brightness, display, &autoOn, &nits);
  printf("tbkeep %s - Touch Bar flicker fix\n", TBKEEP_VERSION);
  printf("Saved level:    %s\n", isnan(saved) ? "auto (fix paused, macOS controls the Touch Bar)"
                                               : [NSString stringWithFormat:@"%.0f%%", saved * 100].UTF8String);
  printf("Dim stage:      %s\n", SkipDimStage() ? "skipped (bar switches straight off)" : "kept (macOS default)");
  printf("Touch Bar now:  %s, %.0f nits\n", autoOn ? "auto-brightness" : "fixed level", nits);
  printf("Background job: %s\n", AgentRunning() ? "running" : "NOT running (run ./install.sh)");
  return 0;
}

static void ApplySaved(BrightnessSystemClient *brightness, long long display) {
  double saved = SavedLevel();
  if (isnan(saved)) ApplyAuto(brightness, display);
  else ApplyLevel(brightness, display, saved);
}

// Walks through levels; the user answers whether the Touch Bar flickers at each one.
static int Try(BrightnessSystemClient *brightness, long long display) {
  NSString *previous = ReadSetting(@"level");
  printf("Find your level. Do this in the room where the flicker happens (a dark room is best).\n"
         "At each step, watch the Touch Bar for about 10 seconds, then answer.\n");
  for (int percent = 20; percent <= 100; percent += 10) {
    double level = percent / 100.0;
    WriteSetting(@"level", [NSString stringWithFormat:@"%.2f", level]);  // the background job follows this
    ApplyLevel(brightness, display, level);
    [NSThread sleepForTimeInterval:0.4];
    double nits = 0;
    CurrentLevel(brightness, display, NULL, &nits);
    char answer = 0;
    while (answer != 'y' && answer != 'n' && answer != 'q') {
      printf("\n%d%% (about %.0f nits). Does it flicker? [y = yes, n = no, q = quit]: ", percent, nits);
      fflush(stdout);
      char line[64];
      if (!fgets(line, sizeof line, stdin)) { answer = 'q'; break; }
      answer = (char)tolower((unsigned char)line[0]);
    }
    if (answer == 'q') break;
    if (answer == 'n') {
      int keep = MIN(100, percent + 10);  // a little extra for cold days
      WriteSetting(@"level", [NSString stringWithFormat:@"%.2f", keep / 100.0]);
      ApplyLevel(brightness, display, keep / 100.0);
      printf("\nNo flicker at %d%%. Saved %d%% (a little higher, for cold days).\n"
             "Change it any time with: tbkeep <number>, for example tbkeep %d\n", percent, keep, MIN(100, keep + 10));
      return 0;
    }
    if (percent == 100)
      printf("\nIt flickers even at full brightness, so this fix can't hide it on your Mac.\n"
             "See \"The permanent fix\" in the README.\n");
  }
  WriteSetting(@"level", previous.length ? previous : [NSString stringWithFormat:@"%.2f", kDefaultLevel]);
  ApplySaved(brightness, display);
  printf("\nStopped. Your previous setting is back.\n");
  return 0;
}

static void PrintHelp(void) {
  printf("tbkeep %s - MacBook Pro Touch Bar flicker fix\n\n"
         "  tbkeep              show status\n"
         "  tbkeep 70           set the Touch Bar level to 70%% (5-100); use a higher number if it flickers\n"
         "  tbkeep try          find the lowest level with no flicker\n"
         "  tbkeep dim on|off   on: skip macOS's dim stage (default); off: keep it\n"
         "  tbkeep auto         pause the fix (macOS controls the Touch Bar again)\n"
         "  tbkeep uninstall    remove tbkeep completely\n"
         "  tbkeep version      version and Mac model (useful for bug reports)\n",
         TBKEEP_VERSION);
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSString *command = argc > 1 ? [@(argv[1]) lowercaseString] : @"status";
    NSString *option = argc > 2 ? [@(argv[2]) lowercaseString] : @"";

    if ([command isEqualToString:@"help"] || [command hasPrefix:@"-"]) {
      PrintHelp();
      return 0;
    }
    if ([command isEqualToString:@"version"]) {
      printf("tbkeep %s on %s\n", TBKEEP_VERSION, MacModel().UTF8String);
      return 0;
    }
    if ([command isEqualToString:@"uninstall"]) {
      NSString *script = [SupportDir() stringByAppendingPathComponent:@"uninstall.sh"];
      if (![NSFileManager.defaultManager isExecutableFileAtPath:script]) {
        fprintf(stderr, "Uninstaller not found at %s\n", script.UTF8String);
        return 1;
      }
      execl("/bin/bash", "bash", script.UTF8String, (char *)NULL);
      return 1;
    }
    if ([command isEqualToString:@"run"]) return Run();

    NSString *missing = MissingAPI();
    if (missing) {
      fprintf(stderr, "tbkeep can't work on this Mac: %s.\n", missing.UTF8String);
      return 1;
    }
    BrightnessSystemClient *brightness = [[NSClassFromString(@"BrightnessSystemClient") alloc] init];
    DFRBrightnessClient *dimming = [[NSClassFromString(@"DFRBrightnessClient") alloc] init];
    long long display = TouchBarDisplay(brightness, dimming);
    if (display < 0) {
      fprintf(stderr, "No Touch Bar found on this Mac.\n");
      return 1;
    }

    if ([command isEqualToString:@"check"]) {
      printf("OK: Touch Bar found and Apple's brightness services are available.\n");
      return 0;
    }
    if ([command isEqualToString:@"status"]) return Status(brightness, display);
    if ([command isEqualToString:@"try"]) return Try(brightness, display);
    if ([command isEqualToString:@"auto"]) {
      WriteSetting(@"level", @"auto");
      ApplyAuto(brightness, display);
      printf("Paused: macOS controls the Touch Bar again. Turn the fix back on with: tbkeep 60\n");
      return 0;
    }
    if ([command isEqualToString:@"dim"] && ([option isEqualToString:@"on"] || [option isEqualToString:@"off"])) {
      WriteSetting(@"dim", [option isEqualToString:@"on"] ? @"skip" : @"keep");
      return Status(brightness, display);
    }

    NSString *number = [command stringByReplacingOccurrencesOfString:@"%" withString:@""];
    BOOL digitsOnly = number.length > 0 &&
                      [number rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
    int percent = number.intValue;
    if (!digitsOnly || percent < 5 || percent > 100) {
      PrintHelp();
      return 1;
    }
    WriteSetting(@"level", [NSString stringWithFormat:@"%.2f", percent / 100.0]);
    ApplyLevel(brightness, display, percent / 100.0);
    [NSThread sleepForTimeInterval:0.5];
    return Status(brightness, display);
  }
}
