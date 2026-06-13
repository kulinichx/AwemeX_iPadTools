#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface AWEElementStackView : UIView
@end

@interface IESLiveStackView : UIView
@end

@interface AWEPlayInteractionViewController : UIViewController
@end

static UIButton *axButton;
static UIView *axPanel;
static BOOL axApplyingElementEffects = NO;

static NSString * const kAXTopAlpha = @"ax_top_alpha";
static NSString * const kAXRightAlpha = @"ax_right_alpha";
static NSString * const kAXScale = @"ax_scale";
static NSString * const kAXIconAlpha = @"ax_icon_alpha";
static NSString * const kAXHideSearch = @"ax_hide_search";
static NSString * const kAXShowButton = @"ax_show_button";

static CGFloat AXFloat(NSString *key, CGFloat def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v floatValue] : def;
}

static BOOL AXBool(NSString *key, BOOL def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v boolValue] : def;
}

static void AXSet(NSString *key, id value) {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIWindow *AXKeyWindow(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    for (UIWindow *w in app.windows) if (w.isKeyWindow) return w;
    return app.windows.firstObject;
}

static BOOL AXIsDescendantOf(UIView *v, UIView *ancestor) {
    if (!v || !ancestor) return NO;
    UIView *cur = v;
    while (cur) {
        if (cur == ancestor) return YES;
        cur = cur.superview;
    }
    return NO;
}

static BOOL AXIsAwemeXPanelView(UIView *v) {
    return AXIsDescendantOf(v, axPanel) || AXIsDescendantOf(v, axButton);
}

static BOOL AXIsElementStackLike(UIView *v) {
    if (!v) return NO;
    Class aweStack = NSClassFromString(@"AWEElementStackView");
    Class iesStack = NSClassFromString(@"IESLiveStackView");
    if (aweStack && [v isKindOfClass:aweStack]) return YES;
    if (iesStack && [v isKindOfClass:iesStack]) return YES;
    NSString *cls = NSStringFromClass(v.class);
    return [cls containsString:@"AWEElementStackView"] || [cls containsString:@"IESLiveStackView"];
}

static BOOL AXIsTopAreaView(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !v.superview) return NO;
    UIWindow *w = AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    // 顶部频道/推荐一栏：只处理顶部小控件，排除搜索框/状态栏/根容器。
    if (f.origin.y < screenH * 0.02 || f.origin.y > screenH * 0.18) return NO;
    if (f.size.width > screenW * 0.65 || f.size.height > 90.0) return NO;
    if (f.origin.x > screenW * 0.72) return NO;
    return YES;
}

static UIViewController *AXFirstViewControllerFromView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static BOOL AXContainsSubviewOfClass(UIView *container, Class cls) {
    if (!container || !cls) return NO;
    for (UIView *sub in container.subviews) {
        if ([sub isKindOfClass:cls]) return YES;
        if (AXContainsSubviewOfClass(sub, cls)) return YES;
    }
    return NO;
}

static BOOL AXStackHasElementClassName(UIView *container, NSString *targetName) {
    if (!container || targetName.length == 0) return NO;
    NSArray *subviews = [container.subviews copy];
    for (NSInteger i = (NSInteger)subviews.count - 1; i >= 0; i--) {
        UIView *sub = subviews[i];
        if ([sub respondsToSelector:@selector(elementClassName)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            NSString *name = [sub performSelector:@selector(elementClassName)];
#pragma clang diagnostic pop
            if ([name isEqualToString:targetName]) return YES;
        }
        if (AXStackHasElementClassName(sub, targetName)) return YES;
    }
    return NO;
}

static BOOL AXIsRightStack(UIView *v) {
    if (!AXIsElementStackLike(v)) return NO;
    if (AXIsAwemeXPanelView(v)) return NO;

    UIViewController *vc = AXFirstViewControllerFromView(v);
    NSString *vcName = vc ? NSStringFromClass(vc.class) : @"";

    // V16：不再用坐标范围兜底判断右侧栏。
    // 之前会误伤 Feed 的滑动/手势容器，导致视频无法上下滑动。
    if (![vcName containsString:@"AWEPlayInteractionViewController"] &&
        ![vcName containsString:@"AWELiveNewPreStreamViewController"]) {
        return NO;
    }

    NSString *label = v.accessibilityLabel ?: @"";
    BOOL hasAvatar = AXContainsSubviewOfClass(v, NSClassFromString(@"AWEPlayInteractionUserAvatarView"));
    BOOL hasUserAvatarElement = AXStackHasElementClassName(v, @"AWEPlayInteractionUserAvatarOptElementElement");
    return [label isEqualToString:@"right"] || hasAvatar || hasUserAvatarElement;
}

static BOOL AXIsTopStack(UIView *v) {
    if (!AXIsElementStackLike(v)) return NO;
    if (AXIsAwemeXPanelView(v)) return NO;
    NSString *label = v.accessibilityLabel ?: @"";
    if ([label isEqualToString:@"top"] || [label isEqualToString:@"center"]) return YES;
    return AXIsTopAreaView(v);
}

static void AXApplyElementEffects(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v)) return;
    if (axApplyingElementEffects) return;

    axApplyingElementEffects = YES;

    if (AXIsRightStack(v)) {
        CGFloat scale = AXFloat(kAXScale, 0.81);
        CGFloat alpha = AXFloat(kAXRightAlpha, 0.80);

        // DYYY iPad 同款：直接作用在 AWEElementStackView 本体，右对齐 + 垂直补偿。
        v.transform = CGAffineTransformIdentity;
        if (scale > 0 && fabs(scale - 1.0) > 0.001) {
            NSArray *subviews = [v.subviews copy];
            CGFloat ty = 0;
            for (UIView *view in subviews) {
                CGFloat viewHeight = view.frame.size.height;
                ty += (viewHeight - viewHeight * scale) / 2;
            }
            CGFloat frameWidth = v.frame.size.width;
            CGFloat rightTX = (frameWidth - frameWidth * scale) / 2;
            CGAffineTransform t = CGAffineTransformMake(scale, 0, 0, scale, rightTX, ty);
            if (!CGAffineTransformEqualToTransform(v.transform, t)) v.transform = t;
        }
        if (fabs(v.alpha - alpha) > 0.001) v.alpha = alpha;
        axApplyingElementEffects = NO;
        return;
    }

    if (AXIsTopStack(v)) {
        CGFloat alpha = AXFloat(kAXTopAlpha, 0.65);
        if (fabs(v.alpha - alpha) > 0.001) v.alpha = alpha;
    }

    axApplyingElementEffects = NO;
}


static void AXRefreshButton(void) {
    if (!axButton) return;
    axButton.hidden = !AXBool(kAXShowButton, YES);
    axButton.alpha = AXFloat(kAXIconAlpha, 0.34);
    axButton.userInteractionEnabled = YES;
    axButton.enabled = YES;
    axButton.layer.zPosition = CGFLOAT_MAX;
    UIWindow *w = AXKeyWindow();
    if (w && axButton.superview == w) [w bringSubviewToFront:axButton];
}




static void AXApplySearchEntranceHide(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v)) return;
    BOOL shouldHide = AXBool(kAXHideSearch, YES);
    if (shouldHide) {
        objc_setAssociatedObject(v, @selector(AXApplySearchEntranceHide), @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        v.hidden = YES;
        v.alpha = 0.0;
        v.userInteractionEnabled = NO;
    } else {
        NSNumber *marked = objc_getAssociatedObject(v, @selector(AXApplySearchEntranceHide));
        if (marked.boolValue) {
            v.hidden = NO;
            v.alpha = 1.0;
            v.userInteractionEnabled = YES;
        }
    }
}

static void AXApplyToSubviews(UIView *view) {
    if (!view) return;
    if (AXIsElementStackLike(view)) {
        AXApplyElementEffects(view);
    } else if (([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIButton.class] || [view isKindOfClass:UIImageView.class]) && AXIsTopAreaView(view)) {
        view.alpha = AXFloat(kAXTopAlpha, 0.65);
    }
    for (UIView *sub in view.subviews) AXApplyToSubviews(sub);
}

static void AXRefreshAllStacks(void) {
    UIWindow *w = AXKeyWindow();
    AXApplyToSubviews(w);
}

static void AXResetTransformRecursive(UIView *view) {
    if (!view) return;
    view.transform = CGAffineTransformIdentity;
    view.layer.anchorPoint = CGPointMake(0.5, 0.5);
    for (UIView *sub in view.subviews) AXResetTransformRecursive(sub);
}

static UILabel *AXLabel(NSString *text, CGFloat value, CGRect frame, CGFloat panelWidth) {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont boldSystemFontOfSize:15];
    [axPanel addSubview:l];
    UILabel *r = [[UILabel alloc] initWithFrame:CGRectMake(panelWidth - 110, frame.origin.y, 80, frame.size.height)];
    r.textAlignment = NSTextAlignmentRight;
    r.textColor = UIColor.whiteColor;
    r.font = [UIFont systemFontOfSize:14];
    r.text = value >= 2.0 ? [NSString stringWithFormat:@"%.2fx", value] : [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    [axPanel addSubview:r];
    return r;
}

@interface AXMenuTarget : NSObject
+ (instancetype)shared;
- (void)openSettings;
- (void)closeSettings;
- (void)resetSettings;
- (void)sliderChanged:(UISlider *)sender;
- (void)switchChanged:(UISwitch *)sender;
@end

@implementation AXMenuTarget
+ (instancetype)shared {
    static AXMenuTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [AXMenuTarget new]; });
    return target;
}

- (void)closeSettings { [axPanel removeFromSuperview]; axPanel = nil; AXRefreshButton(); }

- (void)resetSettings {
    AXSet(kAXTopAlpha, @0.65); AXSet(kAXRightAlpha, @0.80); AXSet(kAXScale, @0.81);
    AXSet(kAXIconAlpha, @0.34); AXSet(kAXHideSearch, @YES); AXSet(kAXShowButton, @YES);
    [self closeSettings];
    AXRefreshAllStacks();
}

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = @[@"", kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha][sender.tag];
    AXSet(key, @(sender.value));
    UILabel *label = [axPanel viewWithTag:8000 + sender.tag];
    label.text = (sender.tag == 3) ? [NSString stringWithFormat:@"%.2fx", sender.value] : [NSString stringWithFormat:@"%.0f%%", sender.value * 100.0];
    AXRefreshButton();
    AXRefreshAllStacks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXRefreshAllStacks(); });
}


- (void)switchChanged:(UISwitch *)sender {
    AXSet(sender.tag == 5 ? kAXHideSearch : kAXShowButton, @(sender.on));
    AXRefreshButton();
    AXRefreshAllStacks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXRefreshAllStacks(); });
}

- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXKeyWindow();
        if (!w) return;
        if (axPanel) { [self closeSettings]; return; }

        CGRect b = UIScreen.mainScreen.bounds;
        CGFloat width = MIN(460.0, b.size.width - 90.0);
        CGFloat height = 500.0;
        axPanel = [[UIView alloc] initWithFrame:CGRectMake((b.size.width - width) / 2.0, (b.size.height - height) / 2.0, width, height)];
        axPanel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.86];
        axPanel.layer.cornerRadius = 20;
        axPanel.clipsToBounds = YES;
        axPanel.userInteractionEnabled = YES;
        axPanel.exclusiveTouch = YES;
        axPanel.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:axPanel];
        [w bringSubviewToFront:axPanel];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, width, 28)];
        title.text = @"AwemeX 设置 V16";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont boldSystemFontOfSize:18];
        title.textAlignment = NSTextAlignmentCenter;
        [axPanel addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(width - 50, 18, 34, 34);
        [close setTitle:@"×" forState:UIControlStateNormal];
        [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:23];
        [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
        [axPanel addSubview:close];

        NSArray *names = @[@"顶部不透明度", @"右侧按钮不透明度", @"右侧按钮缩放比例", @"AX 图标不透明度"];
        NSArray *keys = @[kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha];
        NSArray *defs = @[@0.65, @0.80, @0.81, @0.34];
        for (NSInteger i = 0; i < 4; i++) {
            CGFloat y = 68 + i * 74;
            UILabel *val = AXLabel(names[i], AXFloat(keys[i], [defs[i] floatValue]), CGRectMake(30, y, 230, 24), width);
            val.tag = 8000 + i + 1;
            UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(30, y + 32, width - 60, 30)];
            s.tag = i + 1;
            s.minimumValue = (i == 2) ? 0.50 : 0.05;
            s.maximumValue = (i == 2) ? 1.30 : 1.00;
            s.value = AXFloat(keys[i], [defs[i] floatValue]);
            [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [axPanel addSubview:s];
        }

        NSArray *switchNames = @[@"隐藏右上搜索", @"显示 AX 悬浮按钮"];
        for (NSInteger i = 0; i < 2; i++) {
            CGFloat y = 344 + i * 40;
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(30, y, 230, 30)];
            l.text = switchNames[i];
            l.textColor = UIColor.whiteColor;
            l.font = [UIFont boldSystemFontOfSize:15];
            [axPanel addSubview:l];
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(width - 85, y, 60, 32)];
            sw.tag = i == 0 ? 5 : 6;
            sw.on = AXBool(i == 0 ? kAXHideSearch : kAXShowButton, YES);
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            [axPanel addSubview:sw];
        }

        UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(30, 416, width - 60, 26)];
        note.text = @"V16：移除会抢 Feed 上下滑动的页面级重刷与坐标兜底。";
        note.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.65];
        note.font = [UIFont systemFontOfSize:12];
        note.numberOfLines = 2;
        [axPanel addSubview:note];

        UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
        reset.frame = CGRectMake(50, 448, width - 100, 34);
        reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
        reset.layer.cornerRadius = 9;
        [reset setTitle:@"恢复默认" forState:UIControlStateNormal];
        [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [reset addTarget:self action:@selector(resetSettings) forControlEvents:UIControlEventTouchUpInside];
        [axPanel addSubview:reset];

        AXResetTransformRecursive(axPanel);
        [w bringSubviewToFront:axPanel];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXRefreshAllStacks(); });
    });
}
@end

static void AXShow(void) {
    UIWindow *w = AXKeyWindow();
    if (!w) return;
    if (axButton) {
        if (axButton.superview != w) [w addSubview:axButton];
        AXRefreshButton();
        return;
    }
    axButton = [UIButton buttonWithType:UIButtonTypeSystem];
    axButton.frame = CGRectMake(20, 200, 54, 54);
    axButton.layer.cornerRadius = 27;
    axButton.clipsToBounds = YES;
    axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.70];
    [axButton setTitle:@"AX" forState:UIControlStateNormal];
    [axButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    axButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    axButton.userInteractionEnabled = YES;
    axButton.enabled = YES;
    axButton.layer.zPosition = CGFLOAT_MAX;
    [axButton addTarget:[AXMenuTarget shared] action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:axButton];
    AXRefreshButton();
}

%hook AWEElementStackView
- (void)layoutSubviews { %orig; AXApplyElementEffects((UIView *)self); }
- (void)didMoveToWindow { %orig; AXApplyElementEffects((UIView *)self); }
%end

%hook IESLiveStackView
- (void)layoutSubviews { %orig; AXApplyElementEffects((UIView *)self); }
- (void)didMoveToWindow { %orig; AXApplyElementEffects((UIView *)self); }
%end

%hook AWESearchEntranceView
- (void)layoutSubviews { %orig; AXApplySearchEntranceHide((UIView *)self); }
- (void)didMoveToWindow { %orig; AXApplySearchEntranceHide((UIView *)self); }
%end

%hook AWEHPDiscoverFeedEntranceView
- (void)layoutSubviews { %orig; AXApplySearchEntranceHide((UIView *)self); }
- (void)didMoveToWindow { %orig; AXApplySearchEntranceHide((UIView *)self); }
%end

%hook UILabel
- (void)layoutSubviews {
    %orig;
    if (AXIsTopAreaView((UIView *)self)) self.alpha = AXFloat(kAXTopAlpha, 0.65);
}
%end

%hook UIButton
- (void)layoutSubviews {
    %orig;
    if ((UIView *)self != axButton && AXIsTopAreaView((UIView *)self)) self.alpha = AXFloat(kAXTopAlpha, 0.65);
}
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXShow(); AXRefreshAllStacks(); });
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXShow(); AXRefreshAllStacks(); });
}
