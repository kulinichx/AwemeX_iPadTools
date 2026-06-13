#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface AWEElementStackView : UIView
@end

static UIButton *axButton;
static UIView *axPanel;

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

static BOOL AXIsRightArea(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v)) return NO;
    UIWindow *w = AXKeyWindow();
    if (!w || !v.superview) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    if (f.origin.x < screenW * 0.55) return NO;
    // 排除顶部频道栏/推荐箭头一类控件，避免把顶部文字旁的小三角也当作右侧按钮栏缩放。
    if (f.origin.y < screenH * 0.25) return NO;
    if (f.size.width > screenW * 0.45 || f.size.height > screenH * 0.85) return NO;
    return YES;
}

static BOOL AXIsRightStack(UIView *v) {
    if (![v isKindOfClass:NSClassFromString(@"AWEElementStackView")]) return NO;
    if (AXIsAwemeXPanelView(v)) return NO;
    NSString *label = v.accessibilityLabel;
    if ([label isEqualToString:@"right"]) return YES;
    return AXIsRightArea(v);
}

static void AXSetAnchorPointPreserveFrame(UIView *view, CGPoint anchorPoint) {
    if (!view) return;
    CGPoint oldOrigin = view.frame.origin;
    view.layer.anchorPoint = anchorPoint;
    CGPoint newOrigin = view.frame.origin;
    CGPoint position = view.layer.position;
    position.x -= newOrigin.x - oldOrigin.x;
    position.y -= newOrigin.y - oldOrigin.y;
    view.layer.position = position;
}

static UIView *AXRightScaleContainerForStack(UIView *v) {
    if (!v) return nil;
    UIWindow *w = AXKeyWindow();
    UIView *candidate = v;

    UIView *p = v.superview;
    UIView *gp = p ? p.superview : nil;
    NSArray *candidates = @[gp ?: [NSNull null], p ?: [NSNull null], v];

    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    for (id obj in candidates) {
        if ((id)obj == [NSNull null]) continue;
        UIView *c = (UIView *)obj;
        if (!c || AXIsAwemeXPanelView(c) || !c.superview) continue;
        CGRect f = [c.superview convertRect:c.frame toView:w];
        if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) continue;
        // 只拿视频右侧按钮栏附近的小容器；排除顶部频道栏、设置面板和过大的根容器。
        if (f.origin.x > screenW * 0.55 &&
            f.origin.y > screenH * 0.25 &&
            f.size.width < screenW * 0.38 &&
            f.size.height < screenH * 0.75) {
            candidate = c;
            break;
        }
    }
    return candidate;
}

static void AXResetTransformRecursive(UIView *view) {
    if (!view) return;
    view.transform = CGAffineTransformIdentity;
    view.layer.anchorPoint = CGPointMake(0.5, 0.5);
    for (UIView *sub in view.subviews) AXResetTransformRecursive(sub);
}

static void AXApplyScale(UIView *v) {
    if (!AXIsRightStack(v)) return;
    CGFloat scale = AXFloat(kAXScale, 0.81);
    CGFloat alpha = AXFloat(kAXRightAlpha, 0.80);

    // 原来是每个 AWEElementStackView 自己缩放，图标间距会散。
    // 这里改成缩放右侧按钮栏的共同父容器，并以右下角为锚点，效果更接近 DYYY。
    v.transform = CGAffineTransformIdentity;
    UIView *target = AXRightScaleContainerForStack(v);
    if (!target || AXIsAwemeXPanelView(target)) return;
    AXSetAnchorPointPreserveFrame(target, CGPointMake(1.0, 1.0));
    target.transform = CGAffineTransformMakeScale(scale, scale);
    target.alpha = alpha;
}

static void AXRefreshButton(void) {
    if (!axButton) return;
    axButton.hidden = !AXBool(kAXShowButton, YES);
    axButton.alpha = AXFloat(kAXIconAlpha, 0.34);
}

static UILabel *AXLabel(NSString *text, CGFloat value, CGRect frame) {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont boldSystemFontOfSize:16];
    [axPanel addSubview:l];
    UILabel *r = [[UILabel alloc] initWithFrame:CGRectMake(frame.origin.x + 350, frame.origin.y, 70, frame.size.height)];
    r.tag = 7000 + (NSInteger)(frame.origin.y);
    r.textAlignment = NSTextAlignmentRight;
    r.textColor = UIColor.whiteColor;
    r.font = [UIFont systemFontOfSize:15];
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

- (void)closeSettings { [axPanel removeFromSuperview]; axPanel = nil; }

- (void)resetSettings {
    AXSet(kAXTopAlpha, @0.65); AXSet(kAXRightAlpha, @0.80); AXSet(kAXScale, @0.81);
    AXSet(kAXIconAlpha, @0.34); AXSet(kAXHideSearch, @YES); AXSet(kAXShowButton, @YES);
    [self closeSettings]; AXRefreshButton();
}

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = @[@"", kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha][sender.tag];
    AXSet(key, @(sender.value));
    UILabel *label = [axPanel viewWithTag:8000 + sender.tag];
    label.text = (sender.tag == 3) ? [NSString stringWithFormat:@"%.2fx", sender.value] : [NSString stringWithFormat:@"%.0f%%", sender.value * 100.0];
    AXRefreshButton();
}

- (void)switchChanged:(UISwitch *)sender {
    AXSet(sender.tag == 5 ? kAXHideSearch : kAXShowButton, @(sender.on));
    AXRefreshButton();
}

- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXKeyWindow();
        if (!w) return;
        if (axPanel) { [self closeSettings]; return; }

        CGRect b = UIScreen.mainScreen.bounds;
        CGFloat width = MIN(530.0, b.size.width - 70.0);
        CGFloat height = 610.0;
        axPanel = [[UIView alloc] initWithFrame:CGRectMake((b.size.width-width)/2.0, (b.size.height-height)/2.0, width, height)];
        axPanel.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.86];
        axPanel.layer.cornerRadius = 22;
        axPanel.clipsToBounds = YES;
        [w addSubview:axPanel];
        axPanel.layer.zPosition = 999999;
        axPanel.transform = CGAffineTransformIdentity;

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 22, width, 30)];
        title.text = @"AwemeX 设置 V9";
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont boldSystemFontOfSize:19];
        title.textAlignment = NSTextAlignmentCenter;
        [axPanel addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(width - 55, 20, 36, 36);
        [close setTitle:@"×" forState:UIControlStateNormal];
        [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:24];
        [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
        [axPanel addSubview:close];

        NSArray *names = @[@"顶部不透明度", @"右侧按钮不透明度", @"右侧按钮缩放比例度", @"AX 图标不透明度"];
        NSArray *keys = @[kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha];
        NSArray *defs = @[@0.65, @0.80, @0.81, @0.34];
        for (NSInteger i = 0; i < 4; i++) {
            CGFloat y = 80 + i * 88;
            UILabel *val = AXLabel(names[i], AXFloat(keys[i], [defs[i] floatValue]), CGRectMake(30, y, 250, 26));
            val.tag = 8000 + i + 1;
            UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(30, y + 38, width - 60, 34)];
            s.tag = i + 1;
            s.minimumValue = (i == 2) ? 0.50 : 0.05;
            s.maximumValue = (i == 2) ? 1.30 : 1.00;
            s.value = AXFloat(keys[i], [defs[i] floatValue]);
            [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [axPanel addSubview:s];
        }

        NSArray *switchNames = @[@"隐藏右上搜索", @"显示 AX 悬浮按钮"];
        for (NSInteger i = 0; i < 2; i++) {
            CGFloat y = 435 + i * 48;
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(30, y, 250, 32)];
            l.text = switchNames[i]; l.textColor = UIColor.whiteColor; l.font = [UIFont boldSystemFontOfSize:16];
            [axPanel addSubview:l];
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(width - 85, y, 60, 32)];
            sw.tag = i == 0 ? 5 : 6;
            sw.on = AXBool(i == 0 ? kAXHideSearch : kAXShowButton, YES);
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            [axPanel addSubview:sw];
        }

        UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(30, 525, width - 60, 38)];
        note.text = @"V9：排除顶部推荐箭头；面板按钮和开关强制不参与右侧缩放。";
        note.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.65];
        note.font = [UIFont systemFontOfSize:13];
        note.numberOfLines = 2;
        [axPanel addSubview:note];

        UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
        reset.frame = CGRectMake(50, 565, width - 100, 44);
        reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
        reset.layer.cornerRadius = 10;
        [reset setTitle:@"恢复默认" forState:UIControlStateNormal];
        [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [reset addTarget:self action:@selector(resetSettings) forControlEvents:UIControlEventTouchUpInside];
        [axPanel addSubview:reset];
        // 防止右侧按钮缩放逻辑误伤面板内的关闭按钮/开关。
        AXResetTransformRecursive(axPanel);
    });
}
@end

static void AXShow(void) {
    UIWindow *w = AXKeyWindow();
    if (!w) return;
    if (axButton) { if (axButton.superview != w) [w addSubview:axButton]; AXRefreshButton(); return; }
    axButton = [UIButton buttonWithType:UIButtonTypeSystem];
    axButton.frame = CGRectMake(20, 200, 54, 54);
    axButton.layer.cornerRadius = 27;
    axButton.clipsToBounds = YES;
    axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.70];
    [axButton setTitle:@"AX" forState:UIControlStateNormal];
    [axButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    axButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightMedium];
    [axButton addTarget:[AXMenuTarget shared] action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:axButton];
    AXRefreshButton();
}

%hook AWEElementStackView
- (void)layoutSubviews { %orig; AXApplyScale((UIView *)self); }
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXShow(); });
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXShow(); });
}
