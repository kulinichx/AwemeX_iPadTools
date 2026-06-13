#import "AwemeXSettingsHelper.h"
#import <notify.h>

NSString * const AwemeXSettingsChangedNotification = @"com.awemex.ipadtools.settings.changed";
static NSString * const kAwemeXDarwinNotification = @"com.awemex.ipadtools.settings.changed.darwin";

@implementation AwemeXSettingsHelper {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared {
    static AwemeXSettingsHelper *helper;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ helper = [[AwemeXSettingsHelper alloc] init]; });
    return helper;
}

- (instancetype)init {
    self = [super init];
    if (self) _defaults = [NSUserDefaults standardUserDefaults];
    return self;
}

- (CGFloat)floatForKey:(NSString *)key defaultValue:(CGFloat)defaultValue {
    id obj = [_defaults objectForKey:key];
    if (!obj) return defaultValue;
    CGFloat value = [obj doubleValue];
    if (!isfinite(value)) return defaultValue;
    return value;
}

- (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    id obj = [_defaults objectForKey:key];
    return obj ? [_defaults boolForKey:key] : defaultValue;
}

- (CGFloat)topAlpha { return [self floatForKey:@"awemex_topAlpha" defaultValue:1.0]; }
- (CGFloat)rightAlpha { return [self floatForKey:@"awemex_rightAlpha" defaultValue:1.0]; }
- (CGFloat)likeAlpha { return [self floatForKey:@"awemex_likeAlpha" defaultValue:1.0]; }
- (CGFloat)avatarAlpha { return [self floatForKey:@"awemex_avatarAlpha" defaultValue:1.0]; }
- (CGFloat)bottomTextAlpha { return [self floatForKey:@"awemex_bottomTextAlpha" defaultValue:1.0]; }
- (CGFloat)musicAlpha { return [self floatForKey:@"awemex_musicAlpha" defaultValue:1.0]; }
- (CGFloat)rightScale { return [self floatForKey:@"awemex_rightScale" defaultValue:1.0]; }

- (BOOL)hideTopSearch { return [self boolForKey:@"awemex_hideTopSearch" defaultValue:NO]; }
- (BOOL)floatingButtonEnabled { return [self boolForKey:@"awemex_floatingButton" defaultValue:YES]; }

- (BOOL)newLongPressPanelEnabled { return [self boolForKey:@"awemex_newLongPressPanel" defaultValue:YES]; }
- (BOOL)longPressPanelGlassEnabled { return [self boolForKey:@"awemex_longPressPanelGlass" defaultValue:NO]; }
- (BOOL)longPressPanelDarkModeEnabled { return [self boolForKey:@"awemex_longPressPanelDarkMode" defaultValue:NO]; }
- (BOOL)savePanelGlassEnabled { return [self boolForKey:@"awemex_savePanelGlass" defaultValue:NO]; }
- (CGFloat)panelGlassAlpha { return [self floatForKey:@"awemex_panelGlassAlpha" defaultValue:0.65]; }
- (BOOL)longPressSaveVideoEnabled { return [self boolForKey:@"awemex_longPressSaveVideo" defaultValue:YES]; }
- (BOOL)longPressSaveCoverEnabled { return [self boolForKey:@"awemex_longPressSaveCover" defaultValue:YES]; }
- (BOOL)longPressSaveAudioEnabled { return [self boolForKey:@"awemex_longPressSaveAudio" defaultValue:YES]; }
- (BOOL)longPressSaveImageEnabled { return [self boolForKey:@"awemex_longPressSaveImage" defaultValue:YES]; }
- (BOOL)longPressSaveAllImagesEnabled { return [self boolForKey:@"awemex_longPressSaveAllImages" defaultValue:YES]; }
- (BOOL)longPressGenerateVideoEnabled { return [self boolForKey:@"awemex_longPressGenerateVideo" defaultValue:NO]; }
- (BOOL)longPressCopyTextEnabled { return [self boolForKey:@"awemex_longPressCopyText" defaultValue:NO]; }

- (void)setFloat:(CGFloat)value forKey:(NSString *)key {
    if (!isfinite(value)) value = 1.0;
    [_defaults setDouble:value forKey:key];
    [_defaults synchronize];
    [self postChanged];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [_defaults setBool:value forKey:key];
    [_defaults synchronize];
    [self postChanged];
}

- (void)resetAll {
    NSArray *keys = @[
        @"awemex_topAlpha",
        @"awemex_rightAlpha",
        @"awemex_likeAlpha",
        @"awemex_avatarAlpha",
        @"awemex_bottomTextAlpha",
        @"awemex_musicAlpha",
        @"awemex_rightScale",
        @"awemex_hideTopSearch",
        @"awemex_floatingButton",
        @"awemex_newLongPressPanel",
        @"awemex_longPressPanelGlass",
        @"awemex_longPressPanelDarkMode",
        @"awemex_savePanelGlass",
        @"awemex_panelGlassAlpha",
        @"awemex_longPressSaveVideo",
        @"awemex_longPressSaveCover",
        @"awemex_longPressSaveAudio",
        @"awemex_longPressSaveImage",
        @"awemex_longPressSaveAllImages",
        @"awemex_longPressGenerateVideo",
        @"awemex_longPressCopyText"
    ];
    for (NSString *key in keys) [_defaults removeObjectForKey:key];
    [_defaults synchronize];
    [self postChanged];
}

- (void)postChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:AwemeXSettingsChangedNotification object:nil];
    notify_post([kAwemeXDarwinNotification UTF8String]);
}
@end
