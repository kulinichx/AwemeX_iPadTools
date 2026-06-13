#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import "AwemeXSettingsHelper.h"

extern "C" void AwemeXPresentSettingsFromViewController(UIViewController *vc);

static CGFloat gTopAlpha = 1.0;
static CGFloat gRightAlpha = 1.0;
static CGFloat gLikeAlpha = 1.0;
static CGFloat gAvatarAlpha = 1.0;
static CGFloat gBottomTextAlpha = 1.0;
static CGFloat gMusicAlpha = 1.0;
static CGFloat gRightScale = 1.0;
static BOOL gHideTopSearch = NO;
static BOOL gFloatingButtonEnabled = YES;

static BOOL gNewLongPressPanel = YES;
static BOOL gLongPressPanelGlass = NO;
static BOOL gLongPressPanelDark = NO;
static BOOL gSavePanelGlass = NO;
static CGFloat gPanelGlassAlpha = 0.65;
static BOOL gLongPressSaveVideo = YES;
static BOOL gLongPressSaveCover = YES;
static BOOL gLongPressSaveAudio = YES;
static BOOL gLongPressSaveImage = YES;
static BOOL gLongPressSaveAllImages = YES;
static BOOL gLongPressGenerateVideo = NO;
static BOOL gLongPressCopyText = NO;
static const void *kAwemeXOneFingerLongPressKey = &kAwemeXOneFingerLongPressKey;


static NSString * const kAwemeXDarwinNotification = @"com.awemex.ipadtools.settings.changed.darwin";
static const void *kAwemeXOriginalAlphaKey = &kAwemeXOriginalAlphaKey;
static const void *kAwemeXOriginalTransformKey = &kAwemeXOriginalTransformKey;
static const void *kAwemeXOriginalHiddenKey = &kAwemeXOriginalHiddenKey;
static const void *kAwemeXFloatingButtonKey = &kAwemeXFloatingButtonKey;
static const void *kAwemeXGestureKey = &kAwemeXGestureKey;
static const void *kAwemeXEmbeddedEntryKey = &kAwemeXEmbeddedEntryKey;

static inline BOOL AwemeXIsIpad(void) {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
}

static CGFloat AxClamp(CGFloat v, CGFloat min, CGFloat max) {
    if (!isfinite(v)) return max;
    return MIN(MAX(v, min), max);
}

static void AwemeXLoadSettings(void) {
    AwemeXSettingsHelper *h = [AwemeXSettingsHelper shared];
    gTopAlpha = AxClamp([h topAlpha], 0, 1);
    gRightAlpha = AxClamp([h rightAlpha], 0, 1);
    gLikeAlpha = AxClamp([h likeAlpha], 0, 1);
    gAvatarAlpha = AxClamp([h avatarAlpha], 0, 1);
    gBottomTextAlpha = AxClamp([h bottomTextAlpha], 0, 1);
    gMusicAlpha = AxClamp([h musicAlpha], 0, 1);
    gRightScale = AxClamp([h rightScale], 0.5, 1.5);
    gHideTopSearch = [h hideTopSearch];
    gFloatingButtonEnabled = [h floatingButtonEnabled];

    gNewLongPressPanel = [h newLongPressPanelEnabled];
    gLongPressPanelGlass = [h longPressPanelGlassEnabled];
    gLongPressPanelDark = [h longPressPanelDarkModeEnabled];
    gSavePanelGlass = [h savePanelGlassEnabled];
    gPanelGlassAlpha = AxClamp([h panelGlassAlpha], 0, 1);
    gLongPressSaveVideo = [h longPressSaveVideoEnabled];
    gLongPressSaveCover = [h longPressSaveCoverEnabled];
    gLongPressSaveAudio = [h longPressSaveAudioEnabled];
    gLongPressSaveImage = [h longPressSaveImageEnabled];
    gLongPressSaveAllImages = [h longPressSaveAllImagesEnabled];
    gLongPressGenerateVideo = [h longPressGenerateVideoEnabled];
    gLongPressCopyText = [h longPressCopyTextEnabled];

}

static NSString *AxInfo(UIView *v) {
    return [NSString stringWithFormat:@"%@ %@ %@", NSStringFromClass([v class]), v.accessibilityIdentifier ?: @"", [v description]];
}

static BOOL AxChainContains(UIView *v, NSArray<NSString *> *keys) {
    UIView *cur = v;
    NSInteger depth = 0;
    while (cur && depth < 10) {
        NSString *s = AxInfo(cur);
        for (NSString *k in keys) if ([s containsString:k]) return YES;
        cur = cur.superview;
        depth++;
    }
    return NO;
}

static BOOL AxExcluded(UIView *v) {
    NSString *s = AxInfo(v);
    return [s containsString:@"awemex_"] ||
           [s containsString:@"AwemeX"] ||
           [s containsString:@"Keyboard"] ||
           [s containsString:@"UITextField"] ||
           [s containsString:@"UISlider"] ||
           [s containsString:@"UISwitch"] ||
           [s containsString:@"AVPlayer"] ||
           [s containsString:@"PlayerView"] ||
           [s containsString:@"VideoView"] ||
           [s containsString:@"RenderView"];
}

static BOOL AxLooksLikeSearch(UIView *v) {
    NSString *s = AxInfo(v);
    return [s containsString:@"search"] || [s containsString:@"Search"] || [s containsString:@"搜索"];
}

static BOOL AxLooksLikeTop(UIView *v) {
    return AxChainContains(v, @[@"TopBar", @"HPTop", @"NavigationBar", @"Segment", @"Channel", @"Tab"]);
}

static BOOL AxLooksLikeAvatar(UIView *v) {
    return AxChainContains(v, @[@"Avatar", @"avatar", @"UserHead", @"HeadImage", @"Profile", @"头像"]);
}

static BOOL AxLooksLikeRightBarContainer(UIView *v) {
    NSString *s = AxInfo(v);
    CGRect f = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    BOOL rightPosition = f.origin.x > screen.width * 0.58 && f.size.height > 120 && f.size.width < 170;
    BOOL nameHit = [s containsString:@"Right"] || [s containsString:@"right"] || [s containsString:@"Side"] || [s containsString:@"Action"] || [s containsString:@"Interaction"];
    BOOL enoughSubviews = v.subviews.count >= 3;
    return (nameHit && enoughSubviews) || (rightPosition && enoughSubviews);
}

static BOOL AxLooksLikeRightAction(UIView *v) {
    return AxChainContains(v, @[@"Right", @"right", @"Side", @"Action", @"Interaction", @"Digg", @"Like", @"Comment", @"Share", @"Favorite"]);
}

static BOOL AxLooksLikeBottomText(UIView *v) {
    return AxChainContains(v, @[@"Desc", @"Title", @"Bottom", @"bottom", @"Music", @"Feed", @"Aweme"]);
}

static BOOL AxLooksLikeMusic(UIView *v) {
    return AxChainContains(v, @[@"Music", @"music", @"Song", @"Disc", @"唱片", @"音乐"]);
}

static BOOL AxIsTextOrIcon(UIView *v) {
    return [v isKindOfClass:[UILabel class]] || [v isKindOfClass:[UIImageView class]] || [v isKindOfClass:[UIButton class]];
}

static void AxStoreAlpha(UIView *v) {
    if (!objc_getAssociatedObject(v, kAwemeXOriginalAlphaKey))
        objc_setAssociatedObject(v, kAwemeXOriginalAlphaKey, @(v.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AxStoreTransform(UIView *v) {
    if (!objc_getAssociatedObject(v, kAwemeXOriginalTransformKey))
        objc_setAssociatedObject(v, kAwemeXOriginalTransformKey, [NSValue valueWithCGAffineTransform:v.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AxStoreHidden(UIView *v) {
    if (!objc_getAssociatedObject(v, kAwemeXOriginalHiddenKey))
        objc_setAssociatedObject(v, kAwemeXOriginalHiddenKey, @(v.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AxRestoreAlpha(UIView *v) {
    NSNumber *orig = objc_getAssociatedObject(v, kAwemeXOriginalAlphaKey);
    if (orig) {
        v.alpha = [orig doubleValue];
        objc_setAssociatedObject(v, kAwemeXOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static CGFloat AxTargetAlpha(UIView *v, CGFloat base) {
    BOOL hit = NO;
    CGFloat a = base;

    if (AxLooksLikeTop(v) && AxIsTextOrIcon(v)) {
        a *= gTopAlpha;
        hit = YES;
    }

    if (AxLooksLikeRightAction(v) && [v isKindOfClass:[UILabel class]]) {
        a *= gRightAlpha;
        hit = YES;
    }

    if (AxLooksLikeRightAction(v) && ([v isKindOfClass:[UIImageView class]] || [v isKindOfClass:[UIButton class]])) {
        a *= gLikeAlpha;
        hit = YES;
    }

    if (AxLooksLikeAvatar(v)) {
        a *= gAvatarAlpha;
        hit = YES;
    }

    if (AxLooksLikeBottomText(v) && [v isKindOfClass:[UILabel class]]) {
        a *= gBottomTextAlpha;
        hit = YES;
    }

    if (AxLooksLikeMusic(v) && AxIsTextOrIcon(v)) {
        a *= gMusicAlpha;
        hit = YES;
    }

    return hit ? AxClamp(a, 0, 1) : -1;
}

static void AwemeXApplyToView(UIView *v) {
    if (!v || AxExcluded(v)) return;

    if (AxLooksLikeSearch(v)) {
        AxStoreHidden(v);
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

    if (AxLooksLikeRightBarContainer(v)) {
        if (fabs(gRightScale - 1.0) > 0.001) {
            AxStoreTransform(v);
            v.transform = CGAffineTransformMakeScale(gRightScale, gRightScale);
        } else {
            NSValue *origTransform = objc_getAssociatedObject(v, kAwemeXOriginalTransformKey);
            if (origTransform) {
                v.transform = [origTransform CGAffineTransformValue];
                objc_setAssociatedObject(v, kAwemeXOriginalTransformKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }

    CGFloat target = AxTargetAlpha(v, v.alpha);
    if (target >= 0) {
        AxStoreAlpha(v);
        NSNumber *orig = objc_getAssociatedObject(v, kAwemeXOriginalAlphaKey);
        CGFloat base = orig ? [orig doubleValue] : v.alpha;
        CGFloat fixedTarget = AxTargetAlpha(v, base);
        if (fixedTarget >= 0) v.alpha = fixedTarget;
    } else {
        AxRestoreAlpha(v);
    }
}

static void AwemeXApplyTree(UIView *view) {
    if (!view) return;
    AwemeXApplyToView(view);
    for (UIView *sub in view.subviews) AwemeXApplyTree(sub);
}

static void AwemeXApplyAllWindows(void);

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
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.50];
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
    CGFloat r = self.bounds.size.width / 2.0;
    CGPoint c = CGPointMake(_beginCenter.x + t.x, _beginCenter.y + t.y);
    c.x = MAX(r + 8, MIN(superview.bounds.size.width - r - 8, c.x));
    c.y = MAX(r + 40, MIN(superview.bounds.size.height - r - 40, c.y));
    self.center = c;
}
@end


static NSString *AwemeXCollectVisibleText(UIView *view) {
    NSMutableArray *parts = [NSMutableArray array];
    void (^walk)(UIView *) = ^(UIView *v) {
        if ([v isKindOfClass:[UILabel class]]) {
            NSString *t = ((UILabel *)v).text;
            if (t.length > 0 && t.length < 220 && v.alpha > 0.05 && !v.hidden) [parts addObject:t];
        }
        for (UIView *sub in v.subviews) walk(sub);
    };
    walk(view);
    return [parts componentsJoinedByString:@"\n"];
}

static void AwemeXShowLongPressPanel(void) {
    if (!gNewLongPressPanel) return;

    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if (!vc) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AwemeX 长按面板" message:@"保存类按钮已按开关显示；具体保存动作需要继续接入抖音/DYYY保存接口。" preferredStyle:UIAlertControllerStyleActionSheet];

    if (gLongPressSaveVideo) [alert addAction:[UIAlertAction actionWithTitle:@"保存视频" style:UIAlertActionStyleDefault handler:nil]];
    if (gLongPressSaveCover) [alert addAction:[UIAlertAction actionWithTitle:@"保存封面" style:UIAlertActionStyleDefault handler:nil]];
    if (gLongPressSaveAudio) [alert addAction:[UIAlertAction actionWithTitle:@"保存音频" style:UIAlertActionStyleDefault handler:nil]];
    if (gLongPressSaveImage) [alert addAction:[UIAlertAction actionWithTitle:@"保存图片" style:UIAlertActionStyleDefault handler:nil]];
    if (gLongPressSaveAllImages) [alert addAction:[UIAlertAction actionWithTitle:@"保存所有图片" style:UIAlertActionStyleDefault handler:nil]];
    if (gLongPressGenerateVideo) [alert addAction:[UIAlertAction actionWithTitle:@"生成视频" style:UIAlertActionStyleDefault handler:nil]];
    if (gLongPressCopyText) {
        [alert addAction:[UIAlertAction actionWithTitle:@"复制文案" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
            NSString *text = AwemeXCollectVisibleText(UIApplication.sharedApplication.keyWindow);
            if (text.length) UIPasteboard.generalPasteboard.string = text;
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UIPopoverPresentationController *pop = alert.popoverPresentationController;
    if (pop) {
        pop.sourceView = vc.view;
        pop.sourceRect = CGRectMake(vc.view.bounds.size.width / 2.0, vc.view.bounds.size.height / 2.0, 1, 1);
        pop.permittedArrowDirections = 0;
    }
    [vc presentViewController:alert animated:YES completion:nil];
}

static void AwemeXOneFingerLongPress(UIGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    AwemeXLoadSettings();
    AwemeXShowLongPressPanel();
}

static void AwemeXInstallOneFingerLongPress(UIWindow *window) {
    if (!AwemeXIsIpad() || !window || objc_getAssociatedObject(window, kAwemeXOneFingerLongPressKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[UIApplication sharedApplication] action:@selector(awemex_oneFingerLongPress:)];
    lp.minimumPressDuration = 0.55;
    lp.numberOfTouchesRequired = 1;
    lp.cancelsTouchesInView = NO;
    [window addGestureRecognizer:lp];
    objc_setAssociatedObject(window, kAwemeXOneFingerLongPressKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AwemeXOpenSettingsFromGesture(UIGestureRecognizer *gesture) {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    AwemeXPresentSettingsFromViewController(vc);
}

static void AwemeXInstallGesture(UIWindow *window) {
    if (!AwemeXIsIpad() || !window || objc_getAssociatedObject(window, kAwemeXGestureKey)) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:[UIApplication sharedApplication] action:@selector(awemex_openSettingsGesture:)];
    lp.minimumPressDuration = 0.65;
    lp.numberOfTouchesRequired = 2;
    lp.cancelsTouchesInView = NO;
    [window addGestureRecognizer:lp];
    objc_setAssociatedObject(window, kAwemeXGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AwemeXInstallFloatingButton(UIWindow *window) {
    if (!AwemeXIsIpad() || !window || window.hidden) return;
    UIView *oldButton = objc_getAssociatedObject(window, kAwemeXFloatingButtonKey);
    if (!gFloatingButtonEnabled) {
        [oldButton removeFromSuperview];
        objc_setAssociatedObject(window, kAwemeXFloatingButtonKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (oldButton) return;
    NSString *cls = NSStringFromClass([window class]);
    if ([cls containsString:@"UIText"] || [cls containsString:@"Keyboard"]) return;
    CGFloat size = 44;
    AwemeXFloatingButton *button = [[AwemeXFloatingButton alloc] initWithFrame:CGRectMake(window.bounds.size.width - size - 18, window.bounds.size.height * 0.38, size, size)];
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [window addSubview:button];
    objc_setAssociatedObject(window, kAwemeXFloatingButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AwemeXInstallEmbeddedEntry(UINavigationController *nav) {
    if (!AwemeXIsIpad() || !nav.topViewController) return;
    UIViewController *vc = nav.topViewController;
    NSString *title = vc.title ?: vc.navigationItem.title ?: @"";
    NSString *cls = NSStringFromClass([vc class]);
    BOOL likely = [title containsString:@"设置"] || [title containsString:@"我的"] || [title containsString:@"Me"] || [title containsString:@"Profile"] || [cls containsString:@"Setting"] || [cls containsString:@"Profile"] || [cls containsString:@"Mine"];
    if (!likely || objc_getAssociatedObject(vc, kAwemeXEmbeddedEntryKey)) return;
    UIBarButtonItem *ax = [[UIBarButtonItem alloc] initWithTitle:@"AX" style:UIBarButtonItemStylePlain target:[UIApplication sharedApplication] action:@selector(awemex_openSettingsBarButton:)];
    NSMutableArray *items = [NSMutableArray arrayWithArray:vc.navigationItem.rightBarButtonItems ?: @[]];
    [items insertObject:ax atIndex:0];
    vc.navigationItem.rightBarButtonItems = items;
    objc_setAssociatedObject(vc, kAwemeXEmbeddedEntryKey, ax, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void AwemeXApplyAllWindows(void) {
    if (!AwemeXIsIpad()) return;
    AwemeXLoadSettings();
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            AwemeXApplyTree(window);
            AwemeXInstallGesture(window);
            AwemeXInstallOneFingerLongPress(window);
            AwemeXInstallFloatingButton(window);
        }
    });
}

%hook UIApplication
%new
- (void)awemex_oneFingerLongPress:(UILongPressGestureRecognizer *)gesture { AwemeXOneFingerLongPress(gesture); }
%new
- (void)awemex_openSettingsGesture:(UILongPressGestureRecognizer *)gesture { AwemeXOpenSettingsFromGesture(gesture); }
%new
- (void)awemex_openSettingsBarButton:(id)sender {
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    AwemeXPresentSettingsFromViewController(vc);
}
%end

%hook UIWindow
- (void)didMoveToWindow {
    %orig;
    AwemeXLoadSettings();
    AwemeXInstallGesture((UIWindow *)self);
    AwemeXInstallOneFingerLongPress((UIWindow *)self);
    AwemeXInstallFloatingButton((UIWindow *)self);
}
- (void)makeKeyAndVisible {
    %orig;
    AwemeXLoadSettings();
    AwemeXInstallGesture((UIWindow *)self);
    AwemeXInstallOneFingerLongPress((UIWindow *)self);
    AwemeXInstallFloatingButton((UIWindow *)self);
}
%end

%hook UINavigationController
- (void)viewDidAppear:(BOOL)animated { %orig(animated); AwemeXInstallEmbeddedEntry((UINavigationController *)self); }
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated { %orig(viewController, animated); AwemeXInstallEmbeddedEntry((UINavigationController *)self); }
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
    [[NSNotificationCenter defaultCenter] addObserverForName:AwemeXSettingsChangedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) { AwemeXApplyAllWindows(); }];
    int token = 0;
    notify_register_dispatch([kAwemeXDarwinNotification UTF8String], &token, dispatch_get_main_queue(), ^(__unused int t) { AwemeXApplyAllWindows(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AwemeXApplyAllWindows(); });
}
