#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <math.h>

static UIButton *axButton = nil;
static NSTimer *axTimer = nil;
static __weak UIView *axPanelRoot = nil;
static BOOL axOpacityMutation = NO;
static const NSInteger AXPanelTag = 9527010;
static const NSInteger AXFloatingButtonTag = 9527011;

static CGFloat AXFloat(NSString *key, CGFloat def) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return obj ? [obj floatValue] : def;
}

static void AXSetFloat(NSString *key, CGFloat value) {
    [[NSUserDefaults standardUserDefaults] setObject:@(value) forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL AXBool(NSString *key, BOOL def) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return obj ? [obj boolValue] : def;
}

static UIWindow *AXKeyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
        return nil;
    }
    UIWindow *legacyKeyWindow = nil;
    @try { legacyKeyWindow = [app valueForKey:@"keyWindow"]; } @catch (__unused NSException *e) {}
    if (legacyKeyWindow) return legacyKeyWindow;
    NSArray *legacyWindows = nil;
    @try { legacyWindows = [app valueForKey:@"windows"]; } @catch (__unused NSException *e) {}
    return legacyWindows.firstObject;
}

static BOOL AXIsInOurPanel(UIView *view) {
    UIView *v = view;
    while (v) {
        if (v.tag == AXPanelTag || v.tag == AXFloatingButtonTag || v == axPanelRoot) return YES;
        v = v.superview;
    }
    return NO;
}

static UIViewController *AXFirstAvailableViewControllerFromView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
    }
    return nil;
}

static NSString *AXElementClassName(UIView *view) {
    if (!view || ![view respondsToSelector:@selector(elementClassName)]) return nil;
    return ((NSString *(*)(id, SEL))objc_msgSend)(view, @selector(elementClassName));
}

static BOOL AXContainsSubviewOfClass(Class cls, UIView *container) {
    if (!cls || !container) return NO;
    for (UIView *sub in container.subviews) {
        if ([sub isKindOfClass:cls]) return YES;
        if (AXContainsSubviewOfClass(cls, sub)) return YES;
    }
    return NO;
}

static BOOL AXStackHasElementName(UIView *stack) {
    NSArray *names = @[
        @"AWEPlayInteractionUserAvatarOptElementElement",
        @"AWEPlayInteractionLikeElement",
        @"AWEPlayInteractionCommentElement",
        @"AWEPlayInteractionCollectElement",
        @"AWEPlayInteractionFavoriteElement",
        @"AWEPlayInteractionShareElement",
        @"AWEPlayInteractionMusicCoverElement",
        @"AWEPlayInteractionMusicDiskElement"
    ];
    for (UIView *sub in [stack.subviews copy]) {
        NSString *name = AXElementClassName(sub);
        if (name.length && [names containsObject:name]) return YES;
    }
    return NO;
}

static BOOL AXIsRightElementStackView(UIView *stack) {
    if (!stack || AXIsInOurPanel(stack)) return NO;
    UIViewController *vc = AXFirstAvailableViewControllerFromView(stack);
    Class playVCClass = NSClassFromString(@"AWEPlayInteractionViewController");
    if (!playVCClass || ![vc isKindOfClass:playVCClass]) return NO;
    if ([stack.accessibilityLabel isEqualToString:@"right"]) return YES;
    if (AXContainsSubviewOfClass(NSClassFromString(@"AWEPlayInteractionUserAvatarView"), stack)) return YES;
    return AXStackHasElementName(stack);
}

static void AXApplyDYYYRightStackScale(UIView *stack) {
    if (!AXIsRightElementStackView(stack)) return;
    CGFloat scale = AXFloat(@"ax_right_buttons_scale", 1.0);
    scale = MAX(0.50, MIN(1.50, scale));
    CGAffineTransform t = CGAffineTransformIdentity;
    if (fabs(scale - 1.0) >= 0.01) {
        CGFloat ty = 0.0;
        for (UIView *sub in [stack.subviews copy]) ty += (sub.frame.size.height - sub.frame.size.height * scale) / 2.0;
        CGFloat rightTX = (stack.frame.size.width - stack.frame.size.width * scale) / 2.0;
        t = CGAffineTransformMake(scale, 0, 0, scale, rightTX, ty);
    }
    if (!CGAffineTransformEqualToTransform(stack.transform, t)) stack.transform = t;
}

static CGRect AXScreenRect(UIView *view) {
    if (!view || !view.window || !view.superview) return CGRectZero;
    return [view.superview convertRect:view.frame toView:view.window];
}

static BOOL AXContainsToken(UIView *view, NSArray<NSString *> *tokens) {
    NSString *cls = NSStringFromClass(view.class).lowercaseString ?: @"";
    NSString *acc = (view.accessibilityLabel ?: @"").lowercaseString;
    NSString *elem = (AXElementClassName(view) ?: @"").lowercaseString;
    for (NSString *t in tokens) {
        NSString *token = t.lowercaseString;
        if ([cls containsString:token] || [acc containsString:token] || [elem containsString:token]) return YES;
    }
    return NO;
}

static BOOL AXLooksLikeTopTab(UIView *view) {
    if (AXIsInOurPanel(view) || view.hidden || view.alpha < 0.01 || !view.window) return NO;
    CGRect r = AXScreenRect(view);
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    if (CGRectIsEmpty(r) || r.origin.y < 15 || r.origin.y > 120) return NO;
    if (r.size.width < 20 || r.size.width > 160 || r.size.height < 12 || r.size.height > 60) return NO;
    if (CGRectGetMidX(r) < sw * 0.18 || CGRectGetMidX(r) > sw * 0.82) return NO;
    return AXContainsToken(view, @[@"label", @"button", @"tab", @"segment"]);
}

static BOOL AXLooksLikeSearch(UIView *view) {
    if (AXIsInOurPanel(view) || view.hidden || !view.window) return NO;
    CGRect r = AXScreenRect(view);
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    if (r.origin.y > 150 || CGRectGetMidX(r) < sw * 0.55 || r.size.width > 70 || r.size.height > 70) return NO;
    return AXContainsToken(view, @[@"search", @"magnifier", @"discover"]);
}

static BOOL AXLooksLikeRightButtonOrMusic(UIView *view) {
    if (AXIsInOurPanel(view) || view.hidden || view.alpha < 0.01 || !view.window) return NO;
    CGRect r = AXScreenRect(view);
    CGFloat sw = UIScreen.mainScreen.bounds.size.width;
    CGFloat sh = UIScreen.mainScreen.bounds.size.height;
    if (CGRectGetMidX(r) < sw * 0.68 || CGRectGetMidY(r) < sh * 0.22 || CGRectGetMidY(r) > sh * 0.96) return NO;
    if (r.size.width > sw * 0.35 || r.size.height > sh * 0.35) return NO;
    if (AXContainsToken(view, @[@"avatar", @"useravatar", @"like", @"digg", @"favorite", @"collect", @"comment", @"share", @"forward", @"music", @"cover", @"disk", @"disc", @"sound", @"awemeplayinteraction"])) return YES;
    BOOL iconSize = r.size.width >= 18 && r.size.width <= 90 && r.size.height >= 12 && r.size.height <= 90;
    return iconSize && ([view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIButton.class] || [view isKindOfClass:UILabel.class]);
}

static void AXApplyAlphaIfNeeded(UIView *view, CGFloat alpha) {
    if (!view || AXIsInOurPanel(view)) return;
    CGFloat a = MAX(0.0, MIN(1.0, alpha));
    if (fabs(view.alpha - a) < 0.01) return;
    axOpacityMutation = YES;
    view.alpha = a;
    axOpacityMutation = NO;
}

static void AXTraverseApply(UIView *view, CGFloat topAlpha, CGFloat rightAlpha, BOOL hideSearch) {
    if (!view || AXIsInOurPanel(view)) return;
    if (hideSearch && AXLooksLikeSearch(view)) AXApplyAlphaIfNeeded(view, 0.0);
    else if (AXLooksLikeTopTab(view)) AXApplyAlphaIfNeeded(view, topAlpha);
    else if (AXLooksLikeRightButtonOrMusic(view)) AXApplyAlphaIfNeeded(view, rightAlpha);
    for (UIView *sub in [view.subviews copy]) AXTraverseApply(sub, topAlpha, rightAlpha, hideSearch);
}

static void AXApplyVisibleSettings(void) {
    UIWindow *win = AXKeyWindow();
    if (!win) return;
    AXTraverseApply(win, AXFloat(@"ax_top_alpha", 1.0), AXFloat(@"ax_right_buttons_alpha", 1.0), AXBool(@"ax_hide_search", NO));
}

@interface AXSettingsPanel : UIView @end
@implementation AXSettingsPanel
- (UILabel *)label:(NSString *)text y:(CGFloat)y {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(16, y, self.bounds.size.width - 32, 22)];
    label.text = text; label.textColor = UIColor.whiteColor; label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self addSubview:label]; return label;
}
- (UISlider *)sliderKey:(NSString *)key def:(CGFloat)def min:(CGFloat)min max:(CGFloat)max y:(CGFloat)y valueLabel:(UILabel *)valueLabel {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(16, y, self.bounds.size.width - 32, 34)];
    slider.minimumValue = min; slider.maximumValue = max; slider.value = AXFloat(key, def); slider.accessibilityIdentifier = key;
    valueLabel.text = [NSString stringWithFormat:@"%@  %.2f", valueLabel.text, slider.value];
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:slider]; return slider;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame]; if (!self) return nil;
    self.tag = AXPanelTag; self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82]; self.layer.cornerRadius = 18; self.layer.masksToBounds = YES;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 12, frame.size.width - 64, 28)];
    title.text = @"AwemeX AlphaPro V10.4"; title.textColor = UIColor.whiteColor; title.font = [UIFont boldSystemFontOfSize:18]; [self addSubview:title];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; close.frame = CGRectMake(frame.size.width - 48, 10, 36, 36);
    [close setTitle:@"×" forState:UIControlStateNormal]; close.titleLabel.font = [UIFont systemFontOfSize:30]; [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:close];
    CGFloat y = 54;
    UILabel *v1 = [self label:@"顶部推荐/关注透明度" y:y]; y += 22; [self sliderKey:@"ax_top_alpha" def:1.0 min:0.0 max:1.0 y:y valueLabel:v1]; y += 48;
    UILabel *v2 = [self label:@"右侧按钮透明度" y:y]; y += 22; [self sliderKey:@"ax_right_buttons_alpha" def:1.0 min:0.0 max:1.0 y:y valueLabel:v2]; y += 48;
    UILabel *v3 = [self label:@"右侧按钮缩放" y:y]; y += 22; [self sliderKey:@"ax_right_buttons_scale" def:1.0 min:0.5 max:1.5 y:y valueLabel:v3]; y += 52;
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(16, y, 60, 34)]; sw.on = AXBool(@"ax_hide_search", NO); [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged]; [self addSubview:sw];
    UILabel *hide = [[UILabel alloc] initWithFrame:CGRectMake(88, y + 4, frame.size.width - 104, 24)]; hide.text = @"隐藏右上角搜索/放大镜"; hide.textColor = UIColor.whiteColor; hide.font = [UIFont systemFontOfSize:14]; [self addSubview:hide];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]; [self addGestureRecognizer:pan];
    return self;
}
- (void)sliderChanged:(UISlider *)slider { AXSetFloat(slider.accessibilityIdentifier, slider.value); AXApplyVisibleSettings(); }
- (void)switchChanged:(UISwitch *)sw { [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"ax_hide_search"]; [[NSUserDefaults standardUserDefaults] synchronize]; AXApplyVisibleSettings(); }
- (void)closePanel { [self removeFromSuperview]; axPanelRoot = nil; }
- (void)pan:(UIPanGestureRecognizer *)pan { CGPoint t = [pan translationInView:self.superview]; self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y); [pan setTranslation:CGPointZero inView:self.superview]; }
@end

static void AXShowPanel(void) {
    UIWindow *win = AXKeyWindow(); if (!win) return;
    if (axPanelRoot) { [axPanelRoot removeFromSuperview]; axPanelRoot = nil; return; }
    CGFloat w = MIN(340, win.bounds.size.width - 32);
    AXSettingsPanel *panel = [[AXSettingsPanel alloc] initWithFrame:CGRectMake((win.bounds.size.width - w) / 2.0, 110, w, 280)];
    axPanelRoot = panel; [win addSubview:panel];
}

static void AXEnsureButton(void) {
    UIWindow *win = AXKeyWindow(); if (!win) return; if (axButton && axButton.window) return;
    axButton = [UIButton buttonWithType:UIButtonTypeCustom]; axButton.tag = AXFloatingButtonTag; axButton.frame = CGRectMake(12, 180, 48, 48); axButton.layer.cornerRadius = 24;
    axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45]; [axButton setTitle:@"AX" forState:UIControlStateNormal]; [axButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; axButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [axButton addTarget:[UIApplication sharedApplication] action:@selector(ax_openSettingsPanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[UIApplication sharedApplication] action:@selector(ax_panButton:)]; [axButton addGestureRecognizer:pan]; [win addSubview:axButton];
}

%hook AWEElementStackView
- (void)layoutSubviews { %orig; AXApplyDYYYRightStackScale((UIView *)self); }
- (NSArray *)arrangedSubviews { NSArray *ret = %orig; AXApplyDYYYRightStackScale((UIView *)self); return ret; }
%end

%hook UIView
- (void)setAlpha:(CGFloat)alpha {
    if (!axOpacityMutation && !AXIsInOurPanel((UIView *)self)) {
        if (AXLooksLikeRightButtonOrMusic((UIView *)self)) { %orig(MAX(0.0, MIN(1.0, alpha * AXFloat(@"ax_right_buttons_alpha", 1.0)))); return; }
        if (AXLooksLikeTopTab((UIView *)self)) { %orig(MAX(0.0, MIN(1.0, alpha * AXFloat(@"ax_top_alpha", 1.0)))); return; }
    }
    %orig;
}
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig; AXEnsureButton(); AXApplyVisibleSettings();
    if (!axTimer) axTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *timer) { AXEnsureButton(); AXApplyVisibleSettings(); }];
}
%new
- (void)ax_openSettingsPanel { AXShowPanel(); }
%new
- (void)ax_panButton:(UIPanGestureRecognizer *)pan { UIView *view = pan.view; if (!view || !view.superview) return; CGPoint t = [pan translationInView:view.superview]; view.center = CGPointMake(view.center.x + t.x, view.center.y + t.y); [pan setTranslation:CGPointZero inView:view.superview]; }
%end

%ctor {
    @autoreleasepool {
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"ax_top_alpha"] == nil) AXSetFloat(@"ax_top_alpha", 1.0);
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"ax_right_buttons_alpha"] == nil) AXSetFloat(@"ax_right_buttons_alpha", 1.0);
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"ax_right_buttons_scale"] == nil) AXSetFloat(@"ax_right_buttons_scale", 1.0);
    }
}
