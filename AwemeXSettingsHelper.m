#import "AwemeXSettingsHelper.h"
#import <notify.h>

NSString * const AwemeXSettingsChangedNotification = @"com.awemex.ipadtools.settings.changed";
static NSString * const kAwemeXDarwinNotification = @"com.awemex.ipadtools.settings.changed.darwin";

static NSString * const kTopAlpha = @"awemex_topAlpha";
static NSString * const kGlobalAlpha = @"awemex_globalAlpha";
static NSString * const kAvatarAlpha = @"awemex_avatarAlpha";
static NSString * const kRightScale = @"awemex_rightScale";
static NSString * const kHideTopSearch = @"awemex_hideTopSearch";

@implementation AwemeXSettingsHelper {
    NSUserDefaults *_defaults;
}

+ (instancetype)shared {
    static AwemeXSettingsHelper *helper;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        helper = [[AwemeXSettingsHelper alloc] init];
    });
    return helper;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _defaults = [NSUserDefaults standardUserDefaults];
    }
    return self;
}

- (CGFloat)floatForKey:(NSString *)key {
    id obj = [_defaults objectForKey:key];
    if (!obj) return 0.0;
    CGFloat value = [obj doubleValue];
    if (!isfinite(value) || value < 0) return 0.0;
    return value;
}

- (CGFloat)topAlpha { return [self floatForKey:kTopAlpha]; }
- (CGFloat)globalAlpha { return [self floatForKey:kGlobalAlpha]; }
- (CGFloat)avatarAlpha { return [self floatForKey:kAvatarAlpha]; }
- (CGFloat)rightScale { return [self floatForKey:kRightScale]; }
- (BOOL)hideTopSearch { return [_defaults boolForKey:kHideTopSearch]; }

- (void)setFloat:(CGFloat)value forKey:(NSString *)key {
    if (!isfinite(value) || value < 0) value = 0;
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
    NSArray *keys = @[kTopAlpha, kGlobalAlpha, kAvatarAlpha, kRightScale, kHideTopSearch];
    for (NSString *key in keys) {
        [_defaults removeObjectForKey:key];
    }
    [_defaults synchronize];
    [self postChanged];
}

- (void)postChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:AwemeXSettingsChangedNotification object:nil];
    notify_post([kAwemeXDarwinNotification UTF8String]);
}

@end
