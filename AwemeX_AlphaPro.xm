#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@interface AWEElementStackView : UIView
@end

@interface IESLiveStackView : UIView
@end

@interface AWEPlayInteractionViewController : UIViewController
@end

static UIButton *axButton;
static UIView *axPanel;
static BOOL axApplyingElementEffects = NO;
static UILongPressGestureRecognizer *axTwoFingerLongPressGesture = nil;
static UIWindow *axTwoFingerLongPressWindow = nil;

static NSString * const kAXTopAlpha = @"ax_top_alpha";
static NSString * const kAXRightAlpha = @"ax_right_alpha";
static NSString * const kAXScale = @"ax_scale";
static NSString * const kAXIconAlpha = @"ax_icon_alpha";
static NSString * const kAXGlobalAlpha = @"ax_global_alpha";
static NSString * const kAXNicknameScale = @"ax_nickname_scale";
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

static CGFloat AXClamp01(CGFloat v) {
    return MIN(MAX(v, 0.0), 1.0);
}

static CGFloat AXGlobalAlpha(void) {
    return AXClamp01(AXFloat(kAXGlobalAlpha, 1.0));
}

static CGFloat AXEffectiveAlpha(NSString *key, CGFloat def) {
    return AXClamp01(AXFloat(key, def) * AXGlobalAlpha());
}

static char kAXBaseAlphaKey;
static void AXApplyAlphaKeepingBase(UIView *v, CGFloat multiplier) {
    if (!v) return;
    NSNumber *stored = objc_getAssociatedObject(v, &kAXBaseAlphaKey);
    CGFloat baseAlpha = stored ? stored.floatValue : v.alpha;
    if (!stored) objc_setAssociatedObject(v, &kAXBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat finalAlpha = AXClamp01(baseAlpha * multiplier);
    if (fabs(v.alpha - finalAlpha) > 0.001) v.alpha = finalAlpha;
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

static BOOL AXAncestorIsElementStackLike(UIView *v) {
    UIView *cur = v.superview;
    while (cur) {
        if (AXIsElementStackLike(cur)) return YES;
        cur = cur.superview;
    }
    return NO;
}

static BOOL AXIsOverlayLeafView(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !v.superview) return NO;
    if (AXAncestorIsElementStackLike(v)) return NO;
    if (![v isKindOfClass:UILabel.class] && ![v isKindOfClass:UIButton.class] && ![v isKindOfClass:UIImageView.class]) return NO;
    UIWindow *w = v.window ?: AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    if (f.size.width > screenW * 0.75 || f.size.height > 130.0) return NO;

    // 顶部频道、左下昵称文案、底栏文字图标、右侧散落图标/文字。只处理叶子控件，避免影响视频画面和 Feed 滑动层。
    if (AXIsTopAreaView(v)) return YES;
    if (f.origin.y > screenH * 0.60) return YES;
    if (f.origin.x < screenW * 0.26 && f.origin.y > screenH * 0.36) return YES;
    if (f.origin.x > screenW * 0.72 && f.origin.y > screenH * 0.18) return YES;
    return NO;
}

static void AXApplyOverlayLeafAlpha(UIView *v) {
    if (!AXIsOverlayLeafView(v)) return;
    CGFloat alpha = AXIsTopAreaView(v) ? AXEffectiveAlpha(kAXTopAlpha, 0.65) : AXGlobalAlpha();
    AXApplyAlphaKeepingBase(v, alpha);
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


static BOOL AXIsLooseRightAreaStack(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !v.superview) return NO;
    if ([v isKindOfClass:UIScrollView.class]) return NO;
    UIWindow *w = v.window ?: AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;

    // DYYY 的 iPad 版主要靠 AWEElementStackView 本体缩放。部分 iPad 版本
    // 右侧栏拿不到 VC/label/avatar 特征，所以这里保留坐标兜底；但只允许
    // “右侧窄高按钮栏”，排除顶部推荐栏和 Feed 滑动大容器。
    if (f.origin.x < screenW * 0.55) return NO;
    if (f.origin.y < screenH * 0.22) return NO;
    if (f.size.width > MIN(screenW * 0.34, 260.0)) return NO;
    if (f.size.height < 90.0 || f.size.height > screenH * 0.82) return NO;
    if (v.subviews.count < 2) return NO;
    return YES;
}

static BOOL AXIsSafeRightAreaStack(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !v.superview) return NO;
    if ([v isKindOfClass:UIScrollView.class]) return NO;
    UIWindow *w = AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    // 只允许右侧窄按钮栏：避免再次误伤 Feed 上下滑动容器。
    if (f.origin.x < screenW * 0.68) return NO;
    if (f.origin.y < screenH * 0.18) return NO;
    if (f.size.width > screenW * 0.28) return NO;
    if (f.size.height < 80.0 || f.size.height > screenH * 0.78) return NO;
    if (v.subviews.count < 2) return NO;
    return YES;
}

static BOOL AXIsRightStack(UIView *v) {
    if (!AXIsElementStackLike(v)) return NO;
    if (AXIsAwemeXPanelView(v)) return NO;

    NSString *label = v.accessibilityLabel ?: @"";
    BOOL hasAvatar = AXContainsSubviewOfClass(v, NSClassFromString(@"AWEPlayInteractionUserAvatarView"));
    BOOL hasUserAvatarElement = AXStackHasElementClassName(v, @"AWEPlayInteractionUserAvatarOptElementElement");

    // 先认 DYYY 同款特征。
    if ([label isEqualToString:@"right"] || hasAvatar || hasUserAvatarElement) {
        return YES;
    }

    // iPad 上部分版本取不到 AWEPlayInteractionViewController，label 也可能为空。
    // fixed13 能生效就是靠坐标兜底；这里恢复兜底，但不再恢复会卡上下滑的
    // VC 页面级重刷 / setFrame / setBounds 钩子。
    if (AXIsLooseRightAreaStack(v)) return YES;

    UIViewController *vc = AXFirstViewControllerFromView(v);
    NSString *vcName = vc ? NSStringFromClass(vc.class) : @"";
    BOOL inPlayVC = [vcName containsString:@"AWEPlayInteractionViewController"] ||
                    [vcName containsString:@"AWELiveNewPreStreamViewController"];

    return inPlayVC && AXIsSafeRightAreaStack(v);
}

static BOOL AXIsLooseLeftAreaStack(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v) || !v.superview) return NO;
    if ([v isKindOfClass:UIScrollView.class]) return NO;
    UIWindow *w = v.window ?: AXKeyWindow();
    if (!w) return NO;
    CGRect f = [v.superview convertRect:v.frame toView:w];
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGFloat screenH = UIScreen.mainScreen.bounds.size.height;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    if (f.origin.x > screenW * 0.58) return NO;
    if (f.origin.y < screenH * 0.45) return NO;
    if (f.size.width > screenW * 0.75 || f.size.height > screenH * 0.45) return NO;
    if (v.subviews.count < 1) return NO;
    return YES;
}

static BOOL AXIsLeftStack(UIView *v) {
    if (!AXIsElementStackLike(v)) return NO;
    if (AXIsAwemeXPanelView(v)) return NO;

    NSString *label = v.accessibilityLabel ?: @"";
    BOOL hasAnchor = AXContainsSubviewOfClass(v, NSClassFromString(@"AWEFeedAnchorContainerView"));
    BOOL hasDescElement = AXStackHasElementClassName(v, @"AWEPlayInteractionDescriptionElement");
    if ([label isEqualToString:@"left"] || hasAnchor || hasDescElement) return YES;

    return AXIsLooseLeftAreaStack(v);
}

static BOOL AXIsTopStack(UIView *v) {
    if (!AXIsElementStackLike(v)) return NO;
    if (AXIsAwemeXPanelView(v)) return NO;
    NSString *label = v.accessibilityLabel ?: @"";
    if ([label isEqualToString:@"top"] || [label isEqualToString:@"center"]) return YES;
    return AXIsTopAreaView(v);
}

static CGAffineTransform AXRightStackTargetTransform(UIView *v) {
    CGFloat scale = AXFloat(kAXScale, 0.81);
    if (scale <= 0 || fabs(scale - 1.0) <= 0.001) return CGAffineTransformIdentity;

    NSArray *subviews = [v.subviews copy];
    CGFloat ty = 0;
    for (UIView *view in subviews) {
        CGFloat viewHeight = view.frame.size.height;
        ty += (viewHeight - viewHeight * scale) / 2;
    }
    CGFloat frameWidth = v.frame.size.width;
    CGFloat rightTX = (frameWidth - frameWidth * scale) / 2;
    return CGAffineTransformMake(scale, 0, 0, scale, rightTX, ty);
}

static CGAffineTransform AXLeftStackTargetTransform(UIView *v) {
    CGFloat scale = AXFloat(kAXNicknameScale, 1.0);
    if (scale <= 0 || fabs(scale - 1.0) <= 0.001) return CGAffineTransformIdentity;

    NSArray *subviews = [v.subviews copy];
    CGFloat ty = 0;
    for (UIView *view in subviews) {
        CGFloat viewHeight = view.frame.size.height;
        ty += (viewHeight - viewHeight * scale) / 2;
    }
    CGFloat frameWidth = v.frame.size.width;
    CGFloat leftTX = (frameWidth - frameWidth * scale) / 2 - frameWidth * (1 - scale);
    CGAffineTransform t = CGAffineTransformMakeScale(scale, scale);
    return CGAffineTransformTranslate(t, leftTX / scale, ty / scale);
}

static void AXApplyElementEffects(UIView *v) {
    if (!v || AXIsAwemeXPanelView(v)) return;
    if (axApplyingElementEffects) return;

    axApplyingElementEffects = YES;

    if (AXIsRightStack(v)) {
        CGFloat alpha = AXEffectiveAlpha(kAXRightAlpha, 0.80);
        CGAffineTransform t = AXRightStackTargetTransform(v);

        // DYYY iPad 同款：直接作用在 AWEElementStackView 本体。
        // 之前缩放会被系统后续 setTransform(identity) 覆盖；V20 会在 setTransform 里守护。
        if (!CGAffineTransformEqualToTransform(v.transform, t)) v.transform = t;
        AXApplyAlphaKeepingBase(v, alpha);
        axApplyingElementEffects = NO;
        return;
    }

    if (AXIsLeftStack(v)) {
        CGAffineTransform t = AXLeftStackTargetTransform(v);
        if (!CGAffineTransformEqualToTransform(v.transform, t)) v.transform = t;
        AXApplyAlphaKeepingBase(v, AXGlobalAlpha());
        axApplyingElementEffects = NO;
        return;
    }

    if (AXIsTopStack(v)) {
        CGFloat alpha = AXEffectiveAlpha(kAXTopAlpha, 0.65);
        AXApplyAlphaKeepingBase(v, alpha);
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
    } else {
        AXApplyOverlayLeafAlpha(view);
    }
    for (UIView *sub in view.subviews) AXApplyToSubviews(sub);
}

static void AXRefreshAllStacks(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                AXApplyToSubviews(w);
            }
        }
        return;
    }
    for (UIWindow *w in app.windows) AXApplyToSubviews(w);
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
    r.text = [NSString stringWithFormat:@"%.0f%%", value * 100.0];
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

@interface AXTwoFingerLongPressTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handleTwoFingerLongPress:(UILongPressGestureRecognizer *)gesture;
@end

@implementation AXTwoFingerLongPressTarget
+ (instancetype)shared {
    static AXTwoFingerLongPressTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [AXTwoFingerLongPressTarget new]; });
    return target;
}

- (void)handleTwoFingerLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [[AXMenuTarget shared] openSettings];
    });
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *touchedView = touch.view;

    // 不抢 AwemeX 自己面板/悬浮按钮里的触摸，避免拖动 slider、点按钮时被双指长按识别。
    if (AXIsDescendantOf(touchedView, axPanel) || AXIsDescendantOf(touchedView, axButton)) return NO;

    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    // 允许与抖音 Feed 的上下滑、右侧按钮区域原有手势同时存在；配合 cancelsTouchesInView=NO，避免影响 fixed18。
    return YES;
}
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
    AXSet(kAXGlobalAlpha, @1.00); AXSet(kAXTopAlpha, @0.65); AXSet(kAXRightAlpha, @0.80); AXSet(kAXScale, @0.81);
    AXSet(kAXIconAlpha, @0.34); AXSet(kAXNicknameScale, @1.00); AXSet(kAXHideSearch, @YES); AXSet(kAXShowButton, @YES);
    [self closeSettings];
    AXRefreshAllStacks();
}

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = @[@"", kAXGlobalAlpha, kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha, kAXNicknameScale][sender.tag];
    AXSet(key, @(sender.value));
    UILabel *label = [axPanel viewWithTag:8000 + sender.tag];
    label.text = [NSString stringWithFormat:@"%.0f%%", sender.value * 100.0];
    AXRefreshButton();
    AXRefreshAllStacks();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXRefreshAllStacks(); });
}


- (void)switchChanged:(UISwitch *)sender {
    AXSet(sender.tag == 11 ? kAXHideSearch : kAXShowButton, @(sender.on));
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
        CGFloat height = MIN(620.0, b.size.height - 90.0);
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
        title.text = @"AwemeX 设置 V20";
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

        NSArray *names = @[@"设置全局透明", @"顶部不透明度", @"右侧按钮不透明度", @"右侧按钮缩放比例", @"AX 图标不透明度", @"昵称文案缩放"];
        NSArray *keys = @[kAXGlobalAlpha, kAXTopAlpha, kAXRightAlpha, kAXScale, kAXIconAlpha, kAXNicknameScale];
        NSArray *defs = @[@1.00, @0.65, @0.80, @0.81, @0.34, @1.00];
        for (NSInteger i = 0; i < 6; i++) {
            CGFloat y = 62 + i * 61;
            UILabel *val = AXLabel(names[i], AXFloat(keys[i], [defs[i] floatValue]), CGRectMake(30, y, 230, 24), width);
            val.tag = 8000 + i + 1;
            UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(30, y + 32, width - 60, 30)];
            s.tag = i + 1;
            BOOL isScaleSlider = (i == 3 || i == 5);
            s.minimumValue = isScaleSlider ? 0.50 : 0.05;
            s.maximumValue = isScaleSlider ? 1.30 : 1.00;
            s.value = AXFloat(keys[i], [defs[i] floatValue]);
            [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [axPanel addSubview:s];
        }

        NSArray *switchNames = @[@"隐藏右上搜索", @"显示 AX 悬浮按钮"];
        for (NSInteger i = 0; i < 2; i++) {
            CGFloat y = 452 + i * 42;
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(30, y, 230, 30)];
            l.text = switchNames[i];
            l.textColor = UIColor.whiteColor;
            l.font = [UIFont boldSystemFontOfSize:15];
            [axPanel addSubview:l];
            UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(width - 85, y, 60, 32)];
            sw.tag = i == 0 ? 11 : 12;
            sw.on = AXBool(i == 0 ? kAXHideSearch : kAXShowButton, YES);
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            [axPanel addSubview:sw];
        }

        UILabel *note = [[UILabel alloc] initWithFrame:CGRectMake(30, 532, width - 60, 26)];
        note.text = @"V20：新增全局透明和昵称文案缩放；开关区重新排版。";
        note.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.65];
        note.font = [UIFont systemFontOfSize:12];
        note.numberOfLines = 2;
        [axPanel addSubview:note];

        UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
        reset.frame = CGRectMake(50, 570, width - 100, 36);
        reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
        reset.layer.cornerRadius = 9;
        [reset setTitle:@"搞定收工" forState:UIControlStateNormal];
        [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [reset addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
        [axPanel addSubview:reset];

        AXResetTransformRecursive(axPanel);
        [w bringSubviewToFront:axPanel];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXRefreshAllStacks(); });
    });
}
@end

static void AXInstallTwoFingerLongPressGesture(void) {
    UIWindow *w = AXKeyWindow();
    if (!w) return;

    // Window 可能在启动/切前后台后变化；只在当前 keyWindow 上保留一个手势。
    if (axTwoFingerLongPressGesture && axTwoFingerLongPressWindow == w) {
        if (![w.gestureRecognizers containsObject:axTwoFingerLongPressGesture]) {
            [w addGestureRecognizer:axTwoFingerLongPressGesture];
        }
        return;
    }

    if (axTwoFingerLongPressGesture && axTwoFingerLongPressWindow) {
        [axTwoFingerLongPressWindow removeGestureRecognizer:axTwoFingerLongPressGesture];
    }

    AXTwoFingerLongPressTarget *target = [AXTwoFingerLongPressTarget shared];
    axTwoFingerLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:target
                                                                                action:@selector(handleTwoFingerLongPress:)];
    axTwoFingerLongPressGesture.delegate = target;
    axTwoFingerLongPressGesture.numberOfTouchesRequired = 2;
    axTwoFingerLongPressGesture.minimumPressDuration = 0.75;

    // 核心：不取消、不延迟系统原有触摸，避免影响 fixed18 已修好的上下滑和右侧按钮缩放。
    axTwoFingerLongPressGesture.cancelsTouchesInView = NO;
    axTwoFingerLongPressGesture.delaysTouchesBegan = NO;
    axTwoFingerLongPressGesture.delaysTouchesEnded = NO;

    [w addGestureRecognizer:axTwoFingerLongPressGesture];
    axTwoFingerLongPressWindow = w;
}

static void AXShow(void) {
    UIWindow *w = AXKeyWindow();
    if (!w) return;
    if (axButton) {
        if (axButton.superview != w) [w addSubview:axButton];
        AXRefreshButton();
        AXInstallTwoFingerLongPressGesture();
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
    AXInstallTwoFingerLongPressGesture();
}

// AwemeX V25 Overlay Opacity Controls Module
// 作用：给“昵称/文案区域”和“相关搜索条”单独增加透明度控制。
// 用法：作为独立 .xm 加进现有 AwemeX 工程编译，不要直接替换 fixed18/V23 主文件。
// 默认值：昵称文案 100%，相关搜索 55%。


static NSString * const kAXOFNicknameDescAlpha = @"ax_nickname_desc_alpha";
static NSString * const kAXOFRelatedSearchAlpha = @"ax_related_search_alpha";
static char kAXOFBaseAlphaKey;
static char kAXOFSettingsAddedKey;
static UIView *axofPanel = nil;

static CGFloat AXOF_Clamp(CGFloat v) { return MIN(MAX(v, 0.0), 1.0); }

static CGFloat AXOF_Float(NSString *key, CGFloat def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v floatValue] : def;
}

static void AXOF_Set(NSString *key, id value) {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIWindow *AXOF_KeyWindow(void) {
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

static CGRect AXOF_WindowFrame(UIView *v) {
    if (!v || !v.superview) return CGRectZero;
    UIWindow *w = v.window ?: AXOF_KeyWindow();
    return [v.superview convertRect:v.frame toView:w];
}

static NSString *AXOF_ViewText(UIView *v) {
    if ([v isKindOfClass:UILabel.class]) return ((UILabel *)v).text ?: @"";
    if ([v isKindOfClass:UIButton.class]) return [((UIButton *)v) titleForState:UIControlStateNormal] ?: @"";
    if ([v respondsToSelector:@selector(text)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id t = [v performSelector:@selector(text)];
#pragma clang diagnostic pop
        if ([t isKindOfClass:NSString.class]) return t;
    }
    return @"";
}

static BOOL AXOF_IsAwemeXOwnView(UIView *v) {
    UIResponder *r = v;
    while (r) {
        NSString *name = NSStringFromClass(r.class);
        if ([name containsString:@"AXMenuTarget"] || [name containsString:@"AXOFSettingsTarget"]) return YES;
        if ([r isKindOfClass:UILabel.class]) {
            NSString *t = ((UILabel *)r).text ?: @"";
            if ([t containsString:@"AwemeX 设置"] || [t containsString:@"透明度增强"]) return YES;
        }
        if ([r isKindOfClass:UIView.class]) r = ((UIView *)r).superview;
        else r = r.nextResponder;
    }
    return NO;
}

static BOOL AXOF_IsRelatedSearchView(UIView *v) {
    if (!v || !v.superview || AXOF_IsAwemeXOwnView(v)) return NO;
    NSString *cls = NSStringFromClass(v.class);
    NSString *txt = AXOF_ViewText(v);
    if ([txt containsString:@"相关搜索"] || ([txt containsString:@"搜索"] && txt.length <= 28)) return YES;
    if ([cls containsString:@"RelatedSearch"] || [cls containsString:@"RelationSearch"] ||
        [cls containsString:@"SearchEntrance"] || [cls containsString:@"SearchBar"] ||
        [cls containsString:@"SearchHint"] || [cls containsString:@"FeedSearch"]) return YES;

    // 坐标兜底：底部偏上的横向搜索条，只处理叶子文本/图标/按钮，避免误伤 Feed 容器。
    if (![v isKindOfClass:UILabel.class] && ![v isKindOfClass:UIButton.class] && ![v isKindOfClass:UIImageView.class]) return NO;
    CGRect f = AXOF_WindowFrame(v);
    CGSize s = UIScreen.mainScreen.bounds.size;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    BOOL looksLikeBottomSearch = f.origin.y > s.height * 0.48 && f.origin.y < s.height * 0.72 &&
                                 f.origin.x < s.width * 0.18 && f.size.width > s.width * 0.22 &&
                                 f.size.height < 80.0;
    return looksLikeBottomSearch && txt.length > 0 && [txt containsString:@"搜索"];
}

static BOOL AXOF_IsNicknameDescView(UIView *v) {
    if (!v || !v.superview || AXOF_IsAwemeXOwnView(v)) return NO;
    if (![v isKindOfClass:UILabel.class] && ![v isKindOfClass:UIButton.class] && ![v isKindOfClass:UIImageView.class]) return NO;
    if (AXOF_IsRelatedSearchView(v)) return NO;

    NSString *cls = NSStringFromClass(v.class);
    NSString *txt = AXOF_ViewText(v);
    if ([cls containsString:@"Nick"] || [cls containsString:@"Author"] || [cls containsString:@"Desc"] ||
        [cls containsString:@"Caption"] || [cls containsString:@"TitleLabel"] || [cls containsString:@"FeedAnchor"]) return YES;
    if ([txt hasPrefix:@"@"] || [txt containsString:@"#"] || [txt containsString:@"IP属地"] ||
        [txt containsString:@"作者声明"] || [txt containsString:@"虚构演绎"]) return YES;

    CGRect f = AXOF_WindowFrame(v);
    CGSize s = UIScreen.mainScreen.bounds.size;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;

    // iPad 横屏/竖屏都尽量只处理下方昵称文案叶子控件，不处理右侧按钮栏和底部 Tab。
    BOOL leftOrCenterTextArea = f.origin.x < s.width * 0.72 &&
                                f.origin.y > s.height * 0.28 && f.origin.y < s.height * 0.76 &&
                                f.size.width < s.width * 0.82 && f.size.height < 140.0;
    return leftOrCenterTextArea && txt.length > 0;
}

static void AXOF_ApplyAlpha(UIView *v, CGFloat alpha) {
    if (!v) return;
    alpha = AXOF_Clamp(alpha);
    NSNumber *base = objc_getAssociatedObject(v, &kAXOFBaseAlphaKey);
    CGFloat baseAlpha = base ? base.floatValue : v.alpha;
    if (!base) objc_setAssociatedObject(v, &kAXOFBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat finalAlpha = AXOF_Clamp(baseAlpha * alpha);
    if (fabs(v.alpha - finalAlpha) > 0.001) v.alpha = finalAlpha;
}

static void AXOF_ApplyView(UIView *v) {
    if (!v) return;
    if (AXOF_IsRelatedSearchView(v)) {
        AXOF_ApplyAlpha(v, AXOF_Float(kAXOFRelatedSearchAlpha, 0.55));
        return;
    }
    if (AXOF_IsNicknameDescView(v)) {
        AXOF_ApplyAlpha(v, AXOF_Float(kAXOFNicknameDescAlpha, 1.00));
        return;
    }
}

static void AXOF_RefreshRecursive(UIView *v) {
    if (!v) return;
    AXOF_ApplyView(v);
    for (UIView *sub in v.subviews) AXOF_RefreshRecursive(sub);
}

static void AXOF_RefreshAll(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) AXOF_RefreshRecursive(w);
        }
        return;
    }
    for (UIWindow *w in app.windows) AXOF_RefreshRecursive(w);
}

@interface AXOFSettingsTarget : NSObject
+ (instancetype)shared;
- (void)openOpacityPanel;
- (void)closeOpacityPanel;
- (void)sliderChanged:(UISlider *)sender;
@end

@implementation AXOFSettingsTarget
+ (instancetype)shared {
    static AXOFSettingsTarget *t;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ t = [AXOFSettingsTarget new]; });
    return t;
}

- (void)closeOpacityPanel { [axofPanel removeFromSuperview]; axofPanel = nil; }

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = sender.tag == 2501 ? kAXOFNicknameDescAlpha : kAXOFRelatedSearchAlpha;
    AXOF_Set(key, @(sender.value));
    UILabel *val = [axofPanel viewWithTag:sender.tag + 100];
    val.text = [NSString stringWithFormat:@"%.0f%%", sender.value * 100.0];
    AXOF_RefreshAll();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXOF_RefreshAll(); });
}

- (void)openOpacityPanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXOF_KeyWindow();
        if (!w) return;
        if (axofPanel) { [self closeOpacityPanel]; return; }
        CGRect b = UIScreen.mainScreen.bounds;
        CGFloat width = MIN(430.0, b.size.width - 80.0);
        CGFloat height = 230.0;
        axofPanel = [[UIView alloc] initWithFrame:CGRectMake((b.size.width - width) / 2.0, (b.size.height - height) / 2.0, width, height)];
        axofPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.86];
        axofPanel.layer.cornerRadius = 18;
        axofPanel.clipsToBounds = YES;
        axofPanel.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:axofPanel];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, width, 26)];
        title.text = @"透明度增强";
        title.textColor = UIColor.whiteColor;
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:17];
        [axofPanel addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(width - 48, 14, 36, 34);
        [close setTitle:@"×" forState:UIControlStateNormal];
        [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:24];
        [close addTarget:self action:@selector(closeOpacityPanel) forControlEvents:UIControlEventTouchUpInside];
        [axofPanel addSubview:close];

        NSArray *names = @[@"昵称/文案不透明度", @"相关搜索不透明度"];
        NSArray *keys = @[kAXOFNicknameDescAlpha, kAXOFRelatedSearchAlpha];
        NSArray *defs = @[@1.00, @0.55];
        for (NSInteger i = 0; i < 2; i++) {
            CGFloat y = 62 + i * 72;
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(28, y, width - 150, 24)];
            l.text = names[i];
            l.textColor = UIColor.whiteColor;
            l.font = [UIFont boldSystemFontOfSize:15];
            [axofPanel addSubview:l];

            UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(width - 100, y, 70, 24)];
            val.textAlignment = NSTextAlignmentRight;
            val.textColor = UIColor.whiteColor;
            val.font = [UIFont systemFontOfSize:14];
            CGFloat cur = AXOF_Float(keys[i], [defs[i] floatValue]);
            val.text = [NSString stringWithFormat:@"%.0f%%", cur * 100.0];
            val.tag = 2601 + i;
            [axofPanel addSubview:val];

            UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(28, y + 30, width - 56, 32)];
            s.tag = 2501 + i;
            s.minimumValue = 0.05;
            s.maximumValue = 1.0;
            s.value = cur;
            [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [axofPanel addSubview:s];
        }
    });
}
@end

static UIView *AXOF_FindAwemeXSettingsPanel(void) {
    UIWindow *w = AXOF_KeyWindow();
    if (!w) return nil;
    for (UIView *v in [w.subviews reverseObjectEnumerator]) {
        for (UIView *sub in v.subviews) {
            if ([sub isKindOfClass:UILabel.class]) {
                NSString *t = ((UILabel *)sub).text ?: @"";
                if ([t containsString:@"AwemeX 设置"]) return v;
            }
        }
    }
    return nil;
}

static void AXOF_AddSettingsEntryButton(void) {
    UIView *panel = AXOF_FindAwemeXSettingsPanel();
    if (!panel) return;
    NSNumber *added = objc_getAssociatedObject(panel, &kAXOFSettingsAddedKey);
    if (added.boolValue) return;

    CGFloat width = panel.bounds.size.width;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(30, MAX(52, panel.bounds.size.height - 98), width - 60, 34);
    btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.16];
    btn.layer.cornerRadius = 9;
    [btn setTitle:@"文案/相关搜索透明度" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [btn addTarget:[AXOFSettingsTarget shared] action:@selector(openOpacityPanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btn];
    objc_setAssociatedObject(panel, &kAXOFSettingsAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook AXMenuTarget
- (void)openSettings {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXOF_AddSettingsEntryButton(); });
}
%end

%hook UIView
- (void)layoutSubviews {
    %orig;
    NSString *cls = NSStringFromClass(self.class);
    if ([cls containsString:@"RelatedSearch"] || [cls containsString:@"SearchEntrance"] || [cls containsString:@"FeedSearch"]) {
        AXOF_ApplyAlpha((UIView *)self, AXOF_Float(kAXOFRelatedSearchAlpha, 0.55));
    }
}
%end


%hook AWEElementStackView
- (void)layoutSubviews { %orig; AXApplyElementEffects((UIView *)self); }
- (void)didMoveToWindow { %orig; AXApplyElementEffects((UIView *)self); }
- (NSArray *)arrangedSubviews { NSArray *r = %orig; AXApplyElementEffects((UIView *)self); return r; }
- (void)setTransform:(CGAffineTransform)transform {
    if (!axApplyingElementEffects && AXIsRightStack((UIView *)self)) {
        CGAffineTransform target = AXRightStackTargetTransform((UIView *)self);
        %orig(target);
        return;
    }
    if (!axApplyingElementEffects && AXIsLeftStack((UIView *)self)) {
        CGAffineTransform target = AXLeftStackTargetTransform((UIView *)self);
        %orig(target);
        return;
    }
    %orig(transform);
}
%end

%hook IESLiveStackView
- (void)layoutSubviews { %orig; AXApplyElementEffects((UIView *)self); }
- (void)didMoveToWindow { %orig; AXApplyElementEffects((UIView *)self); }
- (NSArray *)arrangedSubviews { NSArray *r = %orig; AXApplyElementEffects((UIView *)self); return r; }
- (void)setTransform:(CGAffineTransform)transform {
    if (!axApplyingElementEffects && AXIsRightStack((UIView *)self)) {
        CGAffineTransform target = AXRightStackTargetTransform((UIView *)self);
        %orig(target);
        return;
    }
    if (!axApplyingElementEffects && AXIsLeftStack((UIView *)self)) {
        CGAffineTransform target = AXLeftStackTargetTransform((UIView *)self);
        %orig(target);
        return;
    }
    %orig(transform);
}
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
    AXApplyOverlayLeafAlpha((UIView *)self);
    AXOF_ApplyView((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    AXOF_ApplyView((UIView *)self);
}
%end

%hook UIButton
- (void)layoutSubviews {
    %orig;
    if ((UIView *)self != axButton) AXApplyOverlayLeafAlpha((UIView *)self);
    AXOF_ApplyView((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    AXOF_ApplyView((UIView *)self);
}
%end

%hook UIImageView
- (void)layoutSubviews {
    %orig;
    AXApplyOverlayLeafAlpha((UIView *)self);
    AXOF_ApplyView((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    AXOF_ApplyView((UIView *)self);
}
%end

// AwemeX iPad 单指长按菜单：只追加保存按钮，不改菜单背景/布局
// 用法：把本模块粘贴到现有 AwemeX_AlphaPro.xm 末尾，重新 make package。
// 目标：在 AWEUserActionSheetView 的 actions 里追加：保存视频 / 保存封面 / 保存音频 / 保存图片。
// 注意：这是安全测试模块，默认开启；如果按钮出现但保存失败，说明当前抖音版本的 awemeModel 字段名需要再适配。


static NSString * const kAXAppendSaveButtons = @"ax_append_save_buttons";
static char kAXSaveButtonsInjectedKey;

static BOOL AXSB_Bool(NSString *key, BOOL def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v boolValue] : def;
}

static id AXSB_Send0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static BOOL AXSB_StrHasHTTP(NSString *s) {
    return [s isKindOfClass:NSString.class] && ([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"]);
}

static NSURL *AXSB_URLFromString(NSString *s) {
    if (!AXSB_StrHasHTTP(s)) return nil;
    return [NSURL URLWithString:s];
}

static NSURL *AXSB_FirstURLInObject(id obj, NSInteger depth);

static NSURL *AXSB_FirstURLBySelectors(id obj, NSArray<NSString *> *sels, NSInteger depth) {
    if (!obj || depth <= 0) return nil;
    for (NSString *name in sels) {
        SEL sel = NSSelectorFromString(name);
        id value = AXSB_Send0(obj, sel);
        NSURL *u = AXSB_FirstURLInObject(value, depth - 1);
        if (u) return u;
    }
    return nil;
}

static NSURL *AXSB_FirstURLInObject(id obj, NSInteger depth) {
    if (!obj || depth <= 0) return nil;

    if ([obj isKindOfClass:NSURL.class]) return (NSURL *)obj;
    if ([obj isKindOfClass:NSString.class]) return AXSB_URLFromString((NSString *)obj);

    if ([obj isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)obj) {
            NSURL *u = AXSB_FirstURLInObject(item, depth - 1);
            if (u) return u;
        }
        return nil;
    }

    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSArray *preferred = @[@"urlList", @"url_list", @"urls", @"url", @"URL", @"uri", @"playAddr", @"downloadAddr", @"cover", @"originCover", @"playUrl"];
        for (NSString *k in preferred) {
            NSURL *u = AXSB_FirstURLInObject(dict[k], depth - 1);
            if (u) return u;
        }
        for (id value in dict.allValues) {
            NSURL *u = AXSB_FirstURLInObject(value, depth - 1);
            if (u) return u;
        }
        return nil;
    }

    NSArray *common = @[
        @"urlList", @"URLList", @"url_list", @"urls", @"url", @"URL", @"uri",
        @"playAddr", @"downloadAddr", @"playURL", @"playUrl", @"originURL", @"originUrl",
        @"cover", @"originCover", @"dynamicCover", @"animatedCover", @"coverUrl", @"coverURL",
        @"image", @"imageURL", @"imageUrl", @"imageUrlModel", @"urlModel"
    ];
    return AXSB_FirstURLBySelectors(obj, common, depth - 1);
}

static UIViewController *AXSB_TopVCFrom(UIViewController *vc) {
    if (!vc) return nil;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) return AXSB_TopVCFrom(((UINavigationController *)vc).topViewController);
    if ([vc isKindOfClass:UITabBarController.class]) return AXSB_TopVCFrom(((UITabBarController *)vc).selectedViewController);
    return vc;
}

static UIWindow *AXSB_KeyWindow(void) {
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

static UIViewController *AXSB_FindPlayVCInTree(UIViewController *vc) {
    if (!vc) return nil;
    NSString *name = NSStringFromClass(vc.class);
    if ([name containsString:@"AWEPlayInteractionViewController"] || [name containsString:@"PlayInteraction"]) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *hit = AXSB_FindPlayVCInTree(child);
        if (hit) return hit;
    }
    return nil;
}

static UIViewController *AXSB_CurrentPlayVC(void) {
    UIWindow *w = AXSB_KeyWindow();
    UIViewController *top = AXSB_TopVCFrom(w.rootViewController);
    UIViewController *hit = AXSB_FindPlayVCInTree(top);
    if (hit) return hit;
    return AXSB_FindPlayVCInTree(w.rootViewController);
}

static id AXSB_CurrentAwemeModel(void) {
    UIViewController *vc = AXSB_CurrentPlayVC();
    NSArray *sels = @[@"awemeModel", @"aweme", @"model", @"currentAweme", @"currentAwemeModel", @"currentModel", @"item"];
    for (NSString *name in sels) {
        id value = AXSB_Send0(vc, NSSelectorFromString(name));
        if (value) return value;
    }
    return nil;
}

static NSURL *AXSB_VideoURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id video = AXSB_Send0(aweme, @selector(video));
    NSURL *u = AXSB_FirstURLBySelectors(video ?: aweme, @[@"downloadAddr", @"playAddr", @"h264PlayAddr", @"playApi", @"bitRate", @"video"], 6);
    return u ?: AXSB_FirstURLInObject(video ?: aweme, 5);
}

static NSURL *AXSB_CoverURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id video = AXSB_Send0(aweme, @selector(video));
    NSURL *u = AXSB_FirstURLBySelectors(video ?: aweme, @[@"originCover", @"cover", @"dynamicCover", @"animatedCover", @"coverUrl", @"coverURL"], 5);
    return u;
}

static NSURL *AXSB_AudioURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id music = AXSB_Send0(aweme, @selector(music));
    if (!music) music = AXSB_Send0(aweme, @selector(musicModel));
    NSURL *u = AXSB_FirstURLBySelectors(music ?: aweme, @[@"playUrl", @"playURL", @"playUrlModel", @"downloadUrl", @"downloadURL", @"urlModel"], 6);
    return u;
}

static NSArray<NSURL *> *AXSB_ImageURLsFromAweme(id aweme) {
    if (!aweme) return @[];
    NSMutableArray<NSURL *> *out = [NSMutableArray array];
    NSArray *containers = @[
        AXSB_Send0(aweme, @selector(images)),
        AXSB_Send0(aweme, @selector(imageInfos)),
        AXSB_Send0(aweme, @selector(albumImages)),
        AXSB_Send0(aweme, @selector(imageAlbum)),
        AXSB_Send0(aweme, @selector(imagePostInfo))
    ];
    for (id c in containers) {
        if (!c) continue;
        if ([c isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)c) {
                NSURL *u = AXSB_FirstURLInObject(item, 6);
                if (u && ![out containsObject:u]) [out addObject:u];
            }
        } else {
            NSURL *u = AXSB_FirstURLInObject(c, 6);
            if (u && ![out containsObject:u]) [out addObject:u];
        }
    }
    return out;
}

static void AXSB_Toast(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXSB_KeyWindow();
        if (!w) return;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 260, 44)];
        l.center = CGPointMake(CGRectGetMidX(w.bounds), CGRectGetMidY(w.bounds));
        l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont boldSystemFontOfSize:14];
        l.textAlignment = NSTextAlignmentCenter;
        l.text = text;
        l.layer.cornerRadius = 12;
        l.clipsToBounds = YES;
        l.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:l];
        [UIView animateWithDuration:0.25 delay:1.15 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL finished) { [l removeFromSuperview]; }];
    });
}

static void AXSB_SaveImageURL(NSURL *url, NSString *name) {
    if (!url) { AXSB_Toast([NSString stringWithFormat:@"%@链接为空", name]); return; }
    AXSB_Toast([NSString stringWithFormat:@"正在保存%@…", name]);
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (!img) { AXSB_Toast([NSString stringWithFormat:@"%@保存失败", name]); return; }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
        AXSB_Toast([NSString stringWithFormat:@"%@已保存到相册", name]);
    }] resume];
}

static void AXSB_SaveVideoURL(NSURL *url) {
    if (!url) { AXSB_Toast(@"视频链接为空"); return; }
    AXSB_Toast(@"正在保存视频…");
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!location || error) { AXSB_Toast(@"视频下载失败"); return; }
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"awemex_%@.mp4", NSUUID.UUID.UUIDString]];
        NSURL *dst = [NSURL fileURLWithPath:tmp];
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        NSError *moveErr = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dst error:&moveErr];
        if (moveErr) { AXSB_Toast(@"视频缓存失败"); return; }
        UISaveVideoAtPathToSavedPhotosAlbum(tmp, nil, nil, nil);
        AXSB_Toast(@"视频已保存到相册");
    }];
    [task resume];
}

static void AXSB_ShareAudioURL(NSURL *url) {
    if (!url) { AXSB_Toast(@"音频链接为空"); return; }
    AXSB_Toast(@"正在准备音频…");
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!location || error) { AXSB_Toast(@"音频下载失败"); return; }
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"awemex_audio_%@.m4a", NSUUID.UUID.UUIDString]];
        NSURL *dst = [NSURL fileURLWithPath:tmp];
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dst error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *vc = AXSB_TopVCFrom(AXSB_KeyWindow().rootViewController);
            UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[dst] applicationActivities:nil];
            avc.popoverPresentationController.sourceView = vc.view;
            avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
            [vc presentViewController:avc animated:YES completion:nil];
        });
    }];
    [task resume];
}

static void AXSB_HandleSaveKind(NSString *kind) {
    id aweme = AXSB_CurrentAwemeModel();
    if (!aweme) { AXSB_Toast(@"未找到当前视频模型"); return; }
    if ([kind isEqualToString:@"video"]) {
        AXSB_SaveVideoURL(AXSB_VideoURLFromAweme(aweme));
    } else if ([kind isEqualToString:@"cover"]) {
        AXSB_SaveImageURL(AXSB_CoverURLFromAweme(aweme), @"封面");
    } else if ([kind isEqualToString:@"audio"]) {
        AXSB_ShareAudioURL(AXSB_AudioURLFromAweme(aweme));
    } else if ([kind isEqualToString:@"image"]) {
        NSArray<NSURL *> *urls = AXSB_ImageURLsFromAweme(aweme);
        if (urls.count == 0) { AXSB_Toast(@"图片链接为空"); return; }
        AXSB_Toast([NSString stringWithFormat:@"正在保存%lu张图片…", (unsigned long)urls.count]);
        for (NSURL *u in urls) AXSB_SaveImageURL(u, @"图片");
    }
}

static id AXSB_MakeAction(NSString *title, NSString *kind) {
    Class cls = NSClassFromString(@"AWEUserSheetAction");
    if (!cls) return nil;

    void (^handler)(id) = ^(id action) { AXSB_HandleSaveKind(kind); };
    UIImage *img = nil;
    if (@available(iOS 13.0, *)) {
        NSString *sys = [kind isEqualToString:@"video"] ? @"arrow.down.circle" :
                        [kind isEqualToString:@"cover"] ? @"photo" :
                        [kind isEqualToString:@"audio"] ? @"music.note" : @"photo.on.rectangle";
        img = [UIImage systemImageNamed:sys];
    }

    SEL s1 = NSSelectorFromString(@"actionWithTitle:description:image:imageStyle:handler:");
    if ([cls respondsToSelector:s1]) {
        return ((id (*)(id, SEL, id, id, id, NSInteger, id))objc_msgSend)(cls, s1, title, nil, img, 0, handler);
    }

    SEL s2 = NSSelectorFromString(@"actionWithTitle:image:handler:");
    if ([cls respondsToSelector:s2]) {
        return ((id (*)(id, SEL, id, id, id))objc_msgSend)(cls, s2, title, img, handler);
    }

    SEL s3 = NSSelectorFromString(@"actionWithTitle:handler:");
    if ([cls respondsToSelector:s3]) {
        return ((id (*)(id, SEL, id, id))objc_msgSend)(cls, s3, title, handler);
    }
    return nil;
}

static NSString *AXSB_ActionTitle(id action) {
    id t = AXSB_Send0(action, @selector(title));
    if (!t) t = AXSB_Send0(action, @selector(actionTitle));
    if (!t) t = AXSB_Send0(action, @selector(text));
    return [t isKindOfClass:NSString.class] ? (NSString *)t : nil;
}

static NSArray *AXSB_ActionsByAppendingSaveButtons(NSArray *actions, id sheet) {
    if (!AXSB_Bool(kAXAppendSaveButtons, YES)) return actions;
    if (![actions isKindOfClass:NSArray.class]) return actions;

    NSNumber *done = objc_getAssociatedObject(sheet, &kAXSaveButtonsInjectedKey);
    if (done.boolValue) return actions;

    NSMutableArray *m = [actions mutableCopy];
    NSArray *titles = @[@"保存视频", @"保存封面", @"保存音频", @"保存图片"];
    NSArray *kinds = @[@"video", @"cover", @"audio", @"image"];

    for (NSInteger i = 0; i < titles.count; i++) {
        BOOL exists = NO;
        for (id a in m) {
            NSString *t = AXSB_ActionTitle(a);
            if ([t isEqualToString:titles[i]]) { exists = YES; break; }
        }
        if (!exists) {
            id action = AXSB_MakeAction(titles[i], kinds[i]);
            if (action) [m addObject:action];
        }
    }

    objc_setAssociatedObject(sheet, &kAXSaveButtonsInjectedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return m;
}

%hook AWEUserActionSheetView
- (void)setActions:(NSArray *)actions {
    NSArray *patched = AXSB_ActionsByAppendingSaveButtons(actions, self);
    %orig(patched);
}
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXShow(); AXInstallTwoFingerLongPressGesture(); AXRefreshAllStacks(); AXOF_RefreshAll(); });
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXShow(); AXInstallTwoFingerLongPressGesture(); AXRefreshAllStacks(); AXOF_RefreshAll(); });
}
