#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import "AwemeXSettingsHelper.h"

extern "C" void AwemeXPresentSettingsFromViewController(UIViewController *vc);

static CGFloat gTopAlpha = 0;
static CGFloat gGlobalAlpha = 0;
static CGFloat gAvatarAlpha = 0;
static CGFloat gRightScale = 0;
static BOOL gHideTopSearch = NO;
static NSString * const kAwemeXDarwinNotification = @"com.awemex.ipadtools.settings.changed.darwin";
static const void *kAwemeXOriginalAlphaKey = &kAwemeXOriginalAlphaKey;
static const void *kAwemeXOriginalTransformKey = &kAwemeXOriginalTransformKey;
static const void *kAwemeXOriginalHiddenKey = &kAwemeXOriginalHiddenKey;
static const void *kAwemeXFloatingButtonKey = &kAwemeXFloatingButtonKey;

static inline BOOL AwemeXIsIpad(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

static void AwemeXLoadSettings(void) {
    AwemeXSettingsHelper *h = [AwemeXSettingsHelper shared];
    gTopAlpha = [h topAlpha];
    gGlobalAlpha = [h globalAlpha];
    gAvatarAlpha = [h avatarAlpha];
    gRightScale = [h rightScale];
    gHideTopSearch = [h hideTopSearch];
}

static BOOL AwemeXExcludedView(UIView *v) {
    NSString *cls = NSStringFromClass([v class]);
    NSString *aid = v.accessibilityIdentifier ?: @"";
    return [aid hasPrefix:@"awemex_"] ||
           [cls containsString:@"AwemeX"] ||
           [cls containsString:@"UIKeyboard"] ||
           [cls containsString:@"UIText"] ||
           [cls containsString:@"UISlider"] ||
           [cls containsString:@"UISwitch"];
}

static BOOL AwemeXLooksLikeSearch(UIView *v) {
    NSString *s = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([v class]), [v description]];
    return [s containsString:@"search"] || [s containsString:@"Search"] || [s containsString:@"搜索"];
}

static BOOL AwemeXLooksLikeAvatar(UIView *v) {
    NSString *s = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([v class]), [v description]];
    return [s containsString:@"Avatar"] || [s containsString:@"avatar"] || [s containsString:@"头像"] || [s containsString:@"UserHead"];
}

static BOOL AwemeXLooksLikeTopBar(UIView *v) {
    NSString *cls = NSStringFromClass([v class]);
    return [cls containsString:@"TopBar"] || [cls containsString:@"NavigationBar"] || [cls containsString:@"HPTop"];
}

static BOOL AwemeXLooksLikeRightBar(UIView *v) {
    NSString *cls = NSStringFromClass([v class]);
    NSString *s = [NSString stringWithFormat:@"%@ %@", cls, [v description]];
    return [s containsString:@"Right"] || [s containsString:@"right"] || [s containsString:@"Sidebar"] || [s containsString:@"side"] || [s containsString:@"ActionBar"];
}

static void AwemeXStoreOriginalAlphaIfNeeded(UIView *v) {
    if (!objc_getAssociatedObject(v, kAwemeXOriginalAlphaKey)) {
        objc_setAssociatedObject(v, kAwemeXOriginalAlphaKey, @(v.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void AwemeXStoreOriginalTransformIfNeeded(UIView *v) {
    if (!objc_getAssociatedObject(v, kAwemeXOriginalTransformKey)) {
        objc_setAssociatedObject(v, kAwemeXOriginalTransformKey, [NSValue valueWithCGAffineTransform:v.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void AwemeXStoreOriginalHiddenIfNeeded(UIView *v) {
    if (!objc_getAssociatedObject(v, kAwemeXOriginalHiddenKey)) {
        objc_setAssociatedObject(v, kAwemeXOriginalHiddenKey, @(v.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void AwemeXApplyToView(UIView *v) {
    if (!v || AwemeXExcludedView(v)) return;

    BOOL handledAlpha = NO;
    if (gTopAlpha > 0 && AwemeXLooksLikeTopBar(v)) {
        AwemeXStoreOriginalAlphaIfNeeded(v);
        v.alpha = MIN(MAX(gTopAlpha, 0), 1);
        handledAlpha = YES;
    } else if (gAvatarAlpha > 0 && AwemeXLooksLikeAvatar(v)) {
        AwemeXStoreOriginalAlphaIfNeeded(v);
        v.alpha = MIN(MAX(gAvatarAlpha, 0), 1);
        handledAlpha = YES;
    } else if (gGlobalAlpha > 0) {
        AwemeXStoreOriginalAlphaIfNeeded(v);
        NSNumber *orig = objc_getAssociatedObject(v, kAwemeXOriginalAlphaKey);
        v.alpha = MIN(MAX([orig doubleValue] * gGlobalAlpha, 0), 1);
        handledAlpha = YES;
    }

    if (!handledAlpha) {
        NSNumber *orig = objc_getAssociatedObject(v, kAwemeXOriginalAlphaKey);
        if (orig) {
            v.alpha = [orig doubleValue];
            objc_setAssociatedObject(v, kAwemeXOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    if (gRightScale > 0 && AwemeXLooksLikeRightBar(v)) {
        AwemeXStoreOriginalTransformIfNeeded(v);
        v.transform = CGAffineTransformMakeScale(gRightScale, gRightScale);
    } else {
        NSValue *origTransform = objc_getAssociatedObject(v, kAwemeXOriginalTransformKey);
        if (origTransform) {
            v.transform = [origTransform CGAffineTransformValue];
            objc_setAssociatedObject(v, kAwemeXOriginalTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    if (AwemeXLooksLikeSearch(v)) {
        AwemeXStoreOriginalHiddenIfNeeded(v);
        if (gHideTopSearch) {
            v.hidden = YES;
            v.alpha = 0;
            v.userInteractionEnabled = NO;
        } else {
            NSNumber *origHidden = objc_getAssociatedObject(v, kAwemeXOriginalHiddenKey);
            if (origHidden) v.hidden = [origHidden boolValue];
            v.userInteractionEnabled = YES;
        }
    }
}

static void AwemeXApplyToTree(UIView *view) {
    if (!view) return;
    AwemeXApplyToView(view);
    for (UIView *sub in view.subviews) {
        AwemeXApplyToTree(sub);
    }
}

static void AwemeXApplyAllWindows(void) {
    if (!AwemeXIsIpad()) return;
    AwemeXLoadSettings();
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            AwemeXApplyToTree(window);
        }
    });
}

@interface AwemeXFloatingButton : UIButton
@end

@implementation AwemeXFloatingButton {
    CGPoint _beginCenter;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityIdentifier = @"awemex_floating_button";
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.masksToBounds = YES;
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        [self setTitle:@"AX" forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [self addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)openSettings {
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    AwemeXPresentSettingsFromViewController(vc);
}

- (void)pan:(UIPanGestureRecognizer *)pan {
    UIView *superview = self.superview;
    if (!superview) return;
    if (pan.state == UIGestureRecognizerStateBegan) _beginCenter = self.center;
    CGPoint t = [pan translationInView:superview];
    CGPoint c = CGPointMake(_beginCenter.x + t.x, _beginCenter.y + t.y);
    CGFloat r = self.bounds.size.width / 2.0;
    c.x = MAX(r + 8, MIN(superview.bounds.size.width - r - 8, c.x));
    c.y = MAX(r + 40, MIN(superview.bounds.size.height - r - 40, c.y));
    self.center = c;
}
@end

static void AwemeXInstallFloatingButton(UIWindow *window) {
    if (!AwemeXIsIpad() || !window || window.hidden) return;
    if (objc_getAssociatedObject(window, kAwemeXFloatingButtonKey)) return;
    NSString *cls = NSStringFromClass([window class]);
    if ([cls containsString:@"UIText"] || [cls containsString:@"Keyboard"]) return;

    CGFloat size = 46;
    AwemeXFloatingButton *button = [[AwemeXFloatingButton alloc] initWithFrame:CGRectMake(window.bounds.size.width - size - 18, window.bounds.size.height * 0.38, size, size)];
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [window addSubview:button];
    objc_setAssociatedObject(window, kAwemeXFloatingButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook UIWindow
- (void)didMoveToWindow {
    %orig;
    AwemeXInstallFloatingButton((UIWindow *)self);
}

- (void)makeKeyAndVisible {
    %orig;
    AwemeXInstallFloatingButton((UIWindow *)self);
}
%end

%hook UIView
- (void)didMoveToWindow {
    %orig;
    if (!AwemeXIsIpad()) return;
    AwemeXLoadSettings();
    AwemeXApplyToView((UIView *)self);
}

- (void)layoutSubviews {
    %orig;
    if (!AwemeXIsIpad()) return;
    AwemeXLoadSettings();
    AwemeXApplyToView((UIView *)self);
}
%end

%hook AWEHPTopBarCTAItemView
- (void)didMoveToWindow {
    %orig;
    if (!AwemeXIsIpad()) return;
    AwemeXLoadSettings();
    AwemeXApplyToView((UIView *)self);
}
%end

%hook AWEHPTopBarCTAContainerView
- (void)layoutSubviews {
    %orig;
    if (!AwemeXIsIpad()) return;
    AwemeXLoadSettings();
    for (UIView *v in ((UIView *)self).subviews) AwemeXApplyToView(v);
}
%end

%hook AWEHPTopBarView
- (void)setRightItems:(id)arg1 {
    if (AwemeXIsIpad()) {
        AwemeXLoadSettings();
        if (gHideTopSearch) { %orig(nil); return; }
    }
    %orig(arg1);
}
%end

%ctor {
    AwemeXLoadSettings();
    [[NSNotificationCenter defaultCenter] addObserverForName:AwemeXSettingsChangedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
        AwemeXApplyAllWindows();
    }];

    int token = 0;
    notify_register_dispatch([kAwemeXDarwinNotification UTF8String], &token, dispatch_get_main_queue(), ^(__unused int t) {
        AwemeXApplyAllWindows();
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AwemeXApplyAllWindows();
        for (UIWindow *w in UIApplication.sharedApplication.windows) AwemeXInstallFloatingButton(w);
    });
}
