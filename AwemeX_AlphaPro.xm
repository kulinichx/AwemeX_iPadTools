#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static UIButton *axButton = nil;
static NSTimer *axTimer = nil;

static UIWindow *AXKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in windowScene.windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    return UIApplication.sharedApplication.windows.firstObject;
}

static UIViewController *AXTopVC(void) {
    UIWindow *win = AXKeyWindow();
    UIViewController *vc = win.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static CGFloat AXFloat(NSString *key, CGFloat def) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return obj ? [[NSUserDefaults standardUserDefaults] floatForKey:key] : def;
}

static BOOL AXBool(NSString *key, BOOL def) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return obj ? [[NSUserDefaults standardUserDefaults] boolForKey:key] : def;
}

static NSString *AXInfo(UIView *v) {
    NSMutableString *s = [NSMutableString stringWithString:NSStringFromClass(v.class)];
    if (v.accessibilityIdentifier.length) [s appendFormat:@" %@", v.accessibilityIdentifier];
    if ([v respondsToSelector:@selector(accessibilityLabel)] && v.accessibilityLabel.length) {
        [s appendFormat:@" %@", v.accessibilityLabel];
    }
    return s.lowercaseString;
}

static BOOL AXIsInOurPanel(UIView *v) {
    UIView *cur = v;
    while (cur) {
        if ([NSStringFromClass(cur.class) containsString:@"AXSettings"]) return YES;
        if (cur == axButton) return YES;
        cur = cur.superview;
    }
    return NO;
}

static BOOL AXLooksLikeTopTab(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    if (r.origin.y > screen.height * 0.18) return NO;
    if (r.size.height < 20 || r.size.height > 90) return NO;
    NSString *s = AXInfo(v);
    return [s containsString:@"tab"] ||
           [s containsString:@"channel"] ||
           [s containsString:@"顶部"] ||
           [s containsString:@"推荐"] ||
           [s containsString:@"关注"];
}

static BOOL AXLooksLikeRightAction(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    BOOL pos = r.origin.x > screen.width * 0.68;
    BOOL size = r.size.width >= 28 && r.size.width <= 170 && r.size.height >= 40 && r.size.height <= screen.height * 0.85;
    NSString *s = AXInfo(v);
    BOOL name = [s containsString:@"right"] ||
                [s containsString:@"action"] ||
                [s containsString:@"digg"] ||
                [s containsString:@"comment"] ||
                [s containsString:@"share"] ||
                [s containsString:@"like"] ||
                [s containsString:@"avatar"];
    return pos && size && name;
}

static BOOL AXLooksLikeRightPanelContainer(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;

    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;

    BOOL rightSide = r.origin.x > screen.width * 0.66;
    BOOL narrow = r.size.width >= 42 && r.size.width <= 180;
    BOOL tall = r.size.height >= 180 && r.size.height <= screen.height * 0.86;
    BOOL notFullPage = r.size.width < screen.width * 0.32 && r.size.height < screen.height * 0.90;
    BOOL hasSeveralSubviews = v.subviews.count >= 3;

    if (!(rightSide && narrow && tall && notFullPage && hasSeveralSubviews)) return NO;

    NSInteger matchedChildren = 0;
    for (UIView *sub in v.subviews) {
        CGRect sr = [sub.superview convertRect:sub.frame toView:nil];
        if (sr.origin.x > screen.width * 0.62 &&
            sr.size.width >= 20 && sr.size.width <= 150 &&
            sr.size.height >= 20 && sr.size.height <= 140) {
            matchedChildren++;
        }
    }

    NSString *s = AXInfo(v);
    BOOL nameHint = [s containsString:@"right"] ||
                    [s containsString:@"action"] ||
                    [s containsString:@"interaction"] ||
                    [s containsString:@"feed"] ||
                    [s containsString:@"side"];

    return matchedChildren >= 3 || nameHint;
}

static UIView *AXFindBestRightPanel(UIWindow *win) {
    if (!win) return nil;

    UIView *best = nil;
    CGFloat bestScore = 0;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
    NSInteger count = 0;

    while (stack.count && count < 800) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        count++;

        if (AXLooksLikeRightPanelContainer(v)) {
            CGRect r = [v.superview convertRect:v.frame toView:nil];
            CGFloat score = v.subviews.count * 10 + r.size.height + r.origin.x;
            if (score > bestScore) {
                bestScore = score;
                best = v;
            }
        }

        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
        }
    }

    return best;
}

static void AXApplyVisibleSettings(void) {
    UIWindow *win = AXKeyWindow();
    if (!win) return;

    CGFloat topOpacity = AXFloat(@"ax_top_opacity", 1.0);
    CGFloat rightOpacity = AXFloat(@"ax_right_opacity", 1.0);
    CGFloat rightScale = AXFloat(@"ax_right_scale", 1.0);
    if (rightScale < 0.50) rightScale = 0.50;
    if (rightScale > 1.50) rightScale = 1.50;

    UIView *rightPanel = AXFindBestRightPanel(win);
    if (rightPanel) {
        rightPanel.transform = CGAffineTransformMakeScale(rightScale, rightScale);
        rightPanel.alpha = rightOpacity;
    }

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
    NSInteger count = 0;

    while (stack.count && count < 700) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        count++;

        if (v == axButton || AXIsInOurPanel(v)) continue;
        if (rightPanel && (v == rightPanel || [v isDescendantOfView:rightPanel])) continue;

        if (AXLooksLikeTopTab(v)) {
            v.alpha = topOpacity;
        } else if (!rightPanel && AXLooksLikeRightAction(v)) {
            v.alpha = rightOpacity;
        }

        for (UIView *sub in v.subviews) {
            [stack addObject:sub];
        }
    }
}

@interface AXSettingsViewController : UIViewController
@end

@implementation AXSettingsViewController {
    UISlider *_topSlider;
    UISlider *_rightSlider;
    UISlider *_scaleSlider;
    UISwitch *_floatSwitch;
    UILabel *_topValue;
    UILabel *_rightValue;
    UILabel *_scaleValue;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    card.frame = CGRectMake(0, 0, 420, 470);
    card.center = self.view.center;
    card.layer.cornerRadius = 22;
    card.layer.masksToBounds = YES;
    [self.view addSubview:card];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, 420, 36)];
    title.text = @"AwemeX 设置 V4";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [card.contentView addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(366, 18, 36, 36);
    close.layer.cornerRadius = 18;
    close.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:30];
    close.tintColor = UIColor.whiteColor;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:close];

    [self addLabel:@"顶部不透明度" y:76 card:card];
    _topValue = [self addValueLabelY:76 card:card];
    _topSlider = [self addSliderY:106 key:@"ax_top_opacity" def:1.0 min:0.0 max:1.0 card:card];

    [self addLabel:@"右侧面板不透明度" y:152 card:card];
    _rightValue = [self addValueLabelY:152 card:card];
    _rightSlider = [self addSliderY:182 key:@"ax_right_opacity" def:1.0 min:0.0 max:1.0 card:card];

    [self addLabel:@"右侧播放面板缩放" y:228 card:card];
    _scaleValue = [self addValueLabelY:228 card:card];
    _scaleSlider = [self addSliderY:258 key:@"ax_right_scale" def:1.0 min:0.5 max:1.5 card:card];

    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(24, 300, 372, 40)];
    tip.text = @"缩放只尝试命中播放页右侧竖排面板；如果你的版本没变化，下一版再按截图精确匹配。";
    tip.textColor = [UIColor colorWithWhite:1 alpha:0.72];
    tip.font = [UIFont systemFontOfSize:12];
    tip.numberOfLines = 2;
    [card.contentView addSubview:tip];

    UILabel *floatLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 350, 220, 36)];
    floatLabel.text = @"显示 AX 悬浮按钮";
    floatLabel.textColor = UIColor.whiteColor;
    floatLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:floatLabel];

    _floatSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(335, 351, 60, 36)];
    _floatSwitch.on = AXBool(@"ax_float_enabled", YES);
    [_floatSwitch addTarget:self action:@selector(floatChanged:) forControlEvents:UIControlEventValueChanged];
    [card.contentView addSubview:_floatSwitch];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.frame = CGRectMake(40, 405, 340, 42);
    reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
    reset.layer.cornerRadius = 12;
    [reset setTitle:@"恢复默认" forState:UIControlStateNormal];
    reset.tintColor = UIColor.whiteColor;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:reset];

    [self updateValueLabels];
}

- (void)addLabel:(NSString *)text y:(CGFloat)y card:(UIVisualEffectView *)card {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, y, 240, 24)];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:label];
}

- (UILabel *)addValueLabelY:(CGFloat)y card:(UIVisualEffectView *)card {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(300, y, 96, 24)];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    label.textAlignment = NSTextAlignmentRight;
    label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    [card.contentView addSubview:label];
    return label;
}

- (UISlider *)addSliderY:(CGFloat)y key:(NSString *)key def:(CGFloat)def min:(CGFloat)min max:(CGFloat)max card:(UIVisualEffectView *)card {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(24, y, 372, 32)];
    slider.value = AXFloat(key, def);
    slider.minimumValue = min;
    slider.maximumValue = max;
    slider.accessibilityIdentifier = key;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card.contentView addSubview:slider];
    return slider;
}

- (void)updateValueLabels {
    _topValue.text = [NSString stringWithFormat:@"%.0f%%", _topSlider.value * 100.0];
    _rightValue.text = [NSString stringWithFormat:@"%.0f%%", _rightSlider.value * 100.0];
    _scaleValue.text = [NSString stringWithFormat:@"%.2fx", _scaleSlider.value];
}

- (void)sliderChanged:(UISlider *)sender {
    [[NSUserDefaults standardUserDefaults] setFloat:sender.value forKey:sender.accessibilityIdentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateValueLabels];
    AXApplyVisibleSettings();
}

- (void)floatChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ax_float_enabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (axButton) axButton.hidden = !sender.on;
}

- (void)resetTapped {
    [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_top_opacity"];
    [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_right_opacity"];
    [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_right_scale"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    _topSlider.value = 1.0;
    _rightSlider.value = 1.0;
    _scaleSlider.value = 1.0;
    [self updateValueLabels];
    AXApplyVisibleSettings();
}

- (void)closePanel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

static void AXOpenSettings(void) {
    UIViewController *vc = AXTopVC();
    if (!vc) return;

    AXSettingsViewController *panel = [AXSettingsViewController new];
    panel.modalPresentationStyle = UIModalPresentationOverFullScreen;
    panel.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [vc presentViewController:panel animated:YES completion:nil];
}

static void AXAddButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = AXKeyWindow();
        if (!win || axButton) return;

        axButton = [UIButton buttonWithType:UIButtonTypeCustom];
        axButton.frame = CGRectMake(200, 200, 80, 80);
        axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        axButton.layer.cornerRadius = 40;
        axButton.layer.masksToBounds = YES;
        [axButton setTitle:@"AX" forState:UIControlStateNormal];
        axButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];

        [axButton addTarget:[UIApplication sharedApplication]
                     action:@selector(ax_openPanel)
           forControlEvents:UIControlEventTouchUpInside];

        axButton.hidden = !AXBool(@"ax_float_enabled", YES);

        [win addSubview:axButton];
        [win bringSubviewToFront:axButton];

        if (!axTimer) {
            axTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer *timer) {
                AXApplyVisibleSettings();
                if (axButton && axButton.superview) [axButton.superview bringSubviewToFront:axButton];
            }];
        }
    });
}

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AXAddButton();
        AXApplyVisibleSettings();
    });
}

%new
- (void)ax_openPanel {
    AXOpenSettings();
}

%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AXAddButton();
        AXApplyVisibleSettings();
    });
}
