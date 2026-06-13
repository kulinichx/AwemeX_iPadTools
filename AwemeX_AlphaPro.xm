#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

static UIButton *axButton = nil;
static NSTimer *axTimer = nil;
static __weak UIView *axPanelRoot = nil;
static BOOL axInternalAlphaSet = NO;
static const NSInteger AXPanelTag = 9527010;
static const NSInteger AXFloatingButtonTag = 9527011;
static const NSInteger AXScaledMarkTag = 9527012;

static CGFloat AXFloat(NSString *key, CGFloat def) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return obj ? [obj floatValue] : def;
}

static BOOL AXBool(NSString *key, BOOL def) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return obj ? [obj boolValue] : def;
}

static void AXSetFloat(NSString *key, CGFloat value) {
    [[NSUserDefaults standardUserDefaults] setObject:@(value) forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static void AXSetBool(NSString *key, BOOL value) {
    [[NSUserDefaults standardUserDefaults] setBool:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIWindow *AXKeyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) return w;
        }
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindow *w = ((UIWindowScene *)scene).windows.firstObject;
            if (w) return w;
        }
        return nil;
    }
    UIWindow *legacy = nil;
    @try { legacy = [app valueForKey:@"keyWindow"]; } @catch (__unused NSException *e) {}
    if (legacy) return legacy;
    NSArray *wins = nil;
    @try { wins = [app valueForKey:@"windows"]; } @catch (__unused NSException *e) {}
    return wins.firstObject;
}

static BOOL AXIsOurView(UIView *v) {
    while (v) {
        if (v.tag == AXPanelTag || v.tag == AXFloatingButtonTag || v == axPanelRoot) return YES;
        v = v.superview;
    }
    return NO;
}

static NSString *AXLower(NSString *s) { return s ? s.lowercaseString : @""; }

static NSString *AXClassText(UIView *v) {
    NSMutableString *s = [NSMutableString stringWithString:AXLower(NSStringFromClass(v.class))];
    NSString *acc = AXLower(v.accessibilityLabel);
    if (acc.length) [s appendFormat:@" %@", acc];
    if ([v respondsToSelector:@selector(elementClassName)]) {
        NSString *elem = nil;
        @try { elem = ((NSString *(*)(id, SEL))objc_msgSend)(v, @selector(elementClassName)); } @catch (__unused NSException *e) {}
        if (elem.length) [s appendFormat:@" %@", AXLower(elem)];
    }
    return s;
}

static BOOL AXTextContainsAny(NSString *text, NSArray<NSString *> *tokens) {
    for (NSString *t in tokens) if ([text containsString:t.lowercaseString]) return YES;
    return NO;
}

static CGRect AXWindowRect(UIView *v) {
    if (!v || !v.window || !v.superview) return CGRectZero;
    return [v.superview convertRect:v.frame toView:v.window];
}

static BOOL AXLooksRightControl(UIView *v) {
    if (!v || AXIsOurView(v) || v.hidden || v.alpha <= 0.01 || !v.window) return NO;
    CGRect r = AXWindowRect(v);
    if (CGRectIsEmpty(r)) return NO;
    CGSize s = UIScreen.mainScreen.bounds.size;
    CGFloat midX = CGRectGetMidX(r), midY = CGRectGetMidY(r);
    if (midX < s.width * 0.62) return NO;
    if (midY < s.height * 0.18 || midY > s.height * 0.94) return NO;
    if (r.size.width > s.width * 0.42 || r.size.height > s.height * 0.42) return NO;
    NSString *txt = AXClassText(v);
    if (AXTextContainsAny(txt, @[@"avatar", @"useravatar", @"like", @"digg", @"comment", @"favorite", @"collect", @"share", @"forward", @"music", @"cover", @"disk", @"disc", @"sound", @"awemeplayinteraction"])) return YES;
    if (([v isKindOfClass:UIImageView.class] || [v isKindOfClass:UIButton.class] || [v isKindOfClass:UILabel.class]) && r.size.width >= 12 && r.size.width <= 96 && r.size.height >= 10 && r.size.height <= 96) return YES;
    return NO;
}

static BOOL AXLooksSearch(UIView *v) {
    if (!v || AXIsOurView(v) || v.hidden || !v.window) return NO;
    CGRect r = AXWindowRect(v);
    if (CGRectIsEmpty(r)) return NO;
    CGSize s = UIScreen.mainScreen.bounds.size;
    if (CGRectGetMidY(r) > 150 || CGRectGetMidX(r) < s.width * 0.55) return NO;
    if (r.size.width > 100 || r.size.height > 100) return NO;
    NSString *txt = AXClassText(v);
    if (AXTextContainsAny(txt, @[@"search", @"magnifier", @"discover"])) return YES;
    if ([v isKindOfClass:UIButton.class] || [v isKindOfClass:UIImageView.class]) return YES;
    return NO;
}

static BOOL AXLooksTopTab(UIView *v) {
    if (!v || AXIsOurView(v) || v.hidden || !v.window) return NO;
    CGRect r = AXWindowRect(v);
    if (CGRectIsEmpty(r)) return NO;
    CGSize s = UIScreen.mainScreen.bounds.size;
    if (CGRectGetMidY(r) < 18 || CGRectGetMidY(r) > 125) return NO;
    if (CGRectGetMidX(r) < s.width * 0.18 || CGRectGetMidX(r) > s.width * 0.82) return NO;
    if (r.size.width < 18 || r.size.width > 180 || r.size.height < 10 || r.size.height > 70) return NO;
    NSString *txt = AXClassText(v);
    return AXTextContainsAny(txt, @[@"label", @"button", @"tab", @"segment", @"recommend", @"follow"]);
}

static BOOL AXSubviewHasRightControl(UIView *v, NSInteger depth) {
    if (!v || depth <= 0) return NO;
    for (UIView *sub in [v.subviews copy]) {
        if (AXLooksRightControl(sub)) return YES;
        if (AXSubviewHasRightControl(sub, depth - 1)) return YES;
    }
    return NO;
}

static BOOL AXLooksRightStackContainer(UIView *v) {
    if (!v || AXIsOurView(v) || v.hidden || !v.window) return NO;
    CGRect r = AXWindowRect(v);
    if (CGRectIsEmpty(r)) return NO;
    CGSize s = UIScreen.mainScreen.bounds.size;
    if (CGRectGetMidX(r) < s.width * 0.58) return NO;
    if (CGRectGetMidY(r) < s.height * 0.25 || CGRectGetMidY(r) > s.height * 0.88) return NO;
    if (r.size.width < 24 || r.size.width > s.width * 0.48) return NO;
    if (r.size.height < 80 || r.size.height > s.height * 0.82) return NO;
    NSString *txt = AXClassText(v);
    if (AXTextContainsAny(txt, @[@"elementstack", @"stack", @"right", @"interaction"]) && AXSubviewHasRightControl(v, 3)) return YES;
    NSInteger hits = 0;
    for (UIView *sub in [v.subviews copy]) if (AXLooksRightControl(sub) || AXSubviewHasRightControl(sub, 2)) hits++;
    return hits >= 3;
}

static void AXSetViewAlpha(UIView *v, CGFloat alpha) {
    CGFloat a = MAX(0.0, MIN(1.0, alpha));
    if (fabs(v.alpha - a) < 0.01) return;
    axInternalAlphaSet = YES;
    v.alpha = a;
    axInternalAlphaSet = NO;
}

static void AXApplyScaleToContainer(UIView *v) {
    CGFloat scale = AXFloat(@"ax_right_buttons_scale", 1.0);
    scale = MAX(0.50, MIN(1.50, scale));
    CGAffineTransform t = CGAffineTransformIdentity;
    if (fabs(scale - 1.0) >= 0.01) {
        CGFloat w = v.bounds.size.width;
        CGFloat tx = (w - w * scale) / 2.0;
        t = CGAffineTransformMake(scale, 0, 0, scale, tx, 0);
    }
    if (!CGAffineTransformEqualToTransform(v.transform, t)) v.transform = t;
    v.tag = AXScaledMarkTag;
}

static void AXTraverseApply(UIView *root) {
    if (!root || AXIsOurView(root)) return;
    CGFloat rightAlpha = AXFloat(@"ax_right_buttons_alpha", 1.0);
    CGFloat topAlpha = AXFloat(@"ax_top_alpha", 1.0);
    BOOL hideSearch = AXBool(@"ax_hide_search", NO);
    if (AXLooksRightStackContainer(root)) AXApplyScaleToContainer(root);
    if (hideSearch && AXLooksSearch(root)) AXSetViewAlpha(root, 0.0);
    else if (AXLooksRightControl(root)) AXSetViewAlpha(root, rightAlpha);
    else if (AXLooksTopTab(root)) AXSetViewAlpha(root, topAlpha);
    for (UIView *sub in [root.subviews copy]) AXTraverseApply(sub);
}

static void AXApplyAll(void) {
    UIWindow *w = AXKeyWindow();
    if (!w) return;
    AXTraverseApply(w);
}

@interface AXSettingsPanel : UIView
@end

@implementation AXSettingsPanel
- (UILabel *)makeLabel:(NSString *)text y:(CGFloat)y {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(16, y, self.bounds.size.width - 32, 22)];
    l.text = text; l.textColor = UIColor.whiteColor; l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [self addSubview:l]; return l;
}
- (UISlider *)makeSlider:(NSString *)key def:(CGFloat)def min:(CGFloat)min max:(CGFloat)max y:(CGFloat)y {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(16, y, self.bounds.size.width - 32, 34)];
    s.minimumValue = min; s.maximumValue = max; s.value = AXFloat(key, def); s.accessibilityIdentifier = key;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:s]; return s;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame]; if (!self) return nil;
    self.tag = AXPanelTag; self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.84]; self.layer.cornerRadius = 18;
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, frame.size.width - 64, 30)];
    title.text = @"AwemeX AlphaPro V10.6"; title.textColor = UIColor.whiteColor; title.font = [UIFont boldSystemFontOfSize:17]; [self addSubview:title];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; close.frame = CGRectMake(frame.size.width-48, 8, 40, 36); [close setTitle:@"×" forState:UIControlStateNormal]; close.titleLabel.font=[UIFont systemFontOfSize:30]; [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:close];
    CGFloat y = 52;
    [self makeLabel:@"顶部推荐/关注透明度" y:y]; y += 22; [self makeSlider:@"ax_top_alpha" def:1 min:0 max:1 y:y]; y += 44;
    [self makeLabel:@"右侧按钮透明度" y:y]; y += 22; [self makeSlider:@"ax_right_buttons_alpha" def:1 min:0 max:1 y:y]; y += 44;
    [self makeLabel:@"右侧按钮缩放" y:y]; y += 22; [self makeSlider:@"ax_right_buttons_scale" def:1 min:0.5 max:1.5 y:y]; y += 44;
    UISwitch *search = [[UISwitch alloc] initWithFrame:CGRectMake(16, y, 56, 34)]; search.on = AXBool(@"ax_hide_search", NO); search.accessibilityIdentifier=@"ax_hide_search"; [search addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged]; [self addSubview:search];
    UILabel *sl = [[UILabel alloc] initWithFrame:CGRectMake(88, y+5, frame.size.width-104, 24)]; sl.text=@"隐藏右上搜索"; sl.textColor=UIColor.whiteColor; sl.font=[UIFont systemFontOfSize:14]; [self addSubview:sl]; y += 42;
    UISwitch *hideAX = [[UISwitch alloc] initWithFrame:CGRectMake(16, y, 56, 34)]; hideAX.on = AXBool(@"ax_hide_ax_button", NO); hideAX.accessibilityIdentifier=@"ax_hide_ax_button"; [hideAX addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged]; [self addSubview:hideAX];
    UILabel *hl = [[UILabel alloc] initWithFrame:CGRectMake(88, y+5, frame.size.width-104, 24)]; hl.text=@"隐藏 AX 悬浮图标"; hl.textColor=UIColor.whiteColor; hl.font=[UIFont systemFontOfSize:14]; [self addSubview:hl];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)]; [self addGestureRecognizer:pan];
    return self;
}
- (void)sliderChanged:(UISlider *)s { AXSetFloat(s.accessibilityIdentifier, s.value); AXApplyAll(); }
- (void)switchChanged:(UISwitch *)s { AXSetBool(s.accessibilityIdentifier, s.on); if ([s.accessibilityIdentifier isEqualToString:@"ax_hide_ax_button"] && axButton) axButton.hidden = s.on; AXApplyAll(); }
- (void)closePanel { [self removeFromSuperview]; axPanelRoot = nil; }
- (void)pan:(UIPanGestureRecognizer *)pan { CGPoint t=[pan translationInView:self.superview]; self.center=CGPointMake(self.center.x+t.x,self.center.y+t.y); [pan setTranslation:CGPointZero inView:self.superview]; }
@end

static void AXShowPanel(void) {
    UIWindow *w = AXKeyWindow(); if (!w) return;
    if (axPanelRoot) { [axPanelRoot removeFromSuperview]; axPanelRoot=nil; return; }
    CGFloat width = MIN(350, w.bounds.size.width - 28);
    AXSettingsPanel *p = [[AXSettingsPanel alloc] initWithFrame:CGRectMake((w.bounds.size.width-width)/2.0, 96, width, 330)];
    axPanelRoot = p; [w addSubview:p];
}

static void AXEnsureButton(void) {
    UIWindow *w = AXKeyWindow(); if (!w) return;
    if (axButton && axButton.window == w) { axButton.hidden = AXBool(@"ax_hide_ax_button", NO); return; }
    axButton = [UIButton buttonWithType:UIButtonTypeCustom]; axButton.tag = AXFloatingButtonTag; axButton.frame = CGRectMake(12, 180, 50, 50); axButton.layer.cornerRadius = 25; axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    [axButton setTitle:@"AX" forState:UIControlStateNormal]; [axButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; axButton.titleLabel.font=[UIFont boldSystemFontOfSize:14];
    [axButton addTarget:[UIApplication sharedApplication] action:@selector(ax_openSettingsPanel) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:[UIApplication sharedApplication] action:@selector(ax_panButton:)]; [axButton addGestureRecognizer:pan];
    axButton.hidden = AXBool(@"ax_hide_ax_button", NO); [w addSubview:axButton];
}

static void AXStartTimer(void) {
    if (axTimer) return;
    axTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(__unused NSTimer *timer) { AXEnsureButton(); AXApplyAll(); }];
    [[NSRunLoop mainRunLoop] addTimer:axTimer forMode:NSRunLoopCommonModes];
}

%hook UIView
- (void)didMoveToWindow { %orig; if (self.window) { AXApplyAll(); } }
- (void)layoutSubviews { %orig; if (!AXIsOurView((UIView *)self)) { if (AXLooksRightStackContainer((UIView *)self)) AXApplyScaleToContainer((UIView *)self); } }
- (void)setAlpha:(CGFloat)alpha {
    if (!axInternalAlphaSet && !AXIsOurView((UIView *)self)) {
        if (AXBool(@"ax_hide_search", NO) && AXLooksSearch((UIView *)self)) { %orig(0.0); return; }
        if (AXLooksRightControl((UIView *)self)) { %orig(MAX(0.0, MIN(1.0, alpha * AXFloat(@"ax_right_buttons_alpha", 1.0)))); return; }
        if (AXLooksTopTab((UIView *)self)) { %orig(MAX(0.0, MIN(1.0, alpha * AXFloat(@"ax_top_alpha", 1.0)))); return; }
    }
    %orig;
}
%end

%hook UIApplication
- (void)applicationDidFinishLaunching:(UIApplication *)app { %orig; AXEnsureButton(); AXStartTimer(); }
- (void)applicationDidBecomeActive:(UIApplication *)app { %orig; AXEnsureButton(); AXStartTimer(); AXApplyAll(); }
%new
- (void)ax_openSettingsPanel { AXShowPanel(); }
%new
- (void)ax_panButton:(UIPanGestureRecognizer *)pan { UIView *v=pan.view; if (!v || !v.superview) return; CGPoint t=[pan translationInView:v.superview]; v.center=CGPointMake(v.center.x+t.x,v.center.y+t.y); [pan setTranslation:CGPointZero inView:v.superview]; }
%end

%ctor {
    @autoreleasepool {
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"ax_top_alpha"] == nil) AXSetFloat(@"ax_top_alpha", 1.0);
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"ax_right_buttons_alpha"] == nil) AXSetFloat(@"ax_right_buttons_alpha", 1.0);
        if ([[NSUserDefaults standardUserDefaults] objectForKey:@"ax_right_buttons_scale"] == nil) AXSetFloat(@"ax_right_buttons_scale", 1.0);
        dispatch_async(dispatch_get_main_queue(), ^{ AXEnsureButton(); AXStartTimer(); AXApplyAll(); });
    }
}
