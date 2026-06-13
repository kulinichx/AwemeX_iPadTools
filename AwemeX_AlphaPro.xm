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

static BOOL AXLooksLikeRightButtonItem(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    if (v.hidden || v.alpha <= 0.01) return NO;

    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;

    BOOL rightSide = r.origin.x > screen.width * 0.62;
    BOOL itemSize = r.size.width >= 24 && r.size.width <= 120 && r.size.height >= 24 && r.size.height <= 140;
    BOOL notTooLow = r.origin.y > screen.height * 0.15 && r.origin.y < screen.height * 0.88;

    if (!(rightSide && itemSize && notTooLow)) return NO;

    NSString *s = AXInfo(v);
    BOOL nameHit = [s containsString:@"digg"] ||
                   [s containsString:@"like"] ||
                   [s containsString:@"comment"] ||
                   [s containsString:@"collect"] ||
                   [s containsString:@"favorite"] ||
                   [s containsString:@"share"] ||
                   [s containsString:@"avatar"] ||
                   [s containsString:@"follow"] ||
                   [s containsString:@"right"] ||
                   [s containsString:@"action"];

    BOOL imageLike = [v isKindOfClass:UIImageView.class] ||
                     [v isKindOfClass:UIButton.class] ||
                     [v isKindOfClass:UIControl.class];

    BOOL compactLeaf = v.subviews.count <= 4;

    return nameHit || (imageLike && compactLeaf);
}

static BOOL AXLooksLikeRightButtonLabel(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    if (![v isKindOfClass:UILabel.class]) return NO;

    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;

    BOOL rightSide = r.origin.x > screen.width * 0.62;
    BOOL labelSize = r.size.width >= 10 && r.size.width <= 120 && r.size.height >= 10 && r.size.height <= 50;
    BOOL notTooLow = r.origin.y > screen.height * 0.15 && r.origin.y < screen.height * 0.90;

    return rightSide && labelSize && notTooLow;
}

static BOOL AXLooksLikeTopRightSearch(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    if (v == axButton) return NO;

    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;

    BOOL topRight = r.origin.x > screen.width * 0.70 &&
                    r.origin.y >= 0 &&
                    r.origin.y < screen.height * 0.18;

    BOOL smallButton = r.size.width >= 20 && r.size.width <= 120 &&
                       r.size.height >= 20 && r.size.height <= 80;

    if (!(topRight && smallButton)) return NO;

    NSString *s = AXInfo(v);

    BOOL textHit = [s containsString:@"search"] ||
                   [s containsString:@"magnifier"] ||
                   [s containsString:@"finder"] ||
                   [s containsString:@"搜索"] ||
                   [s containsString:@"放大镜"];

    BOOL classHit = [v isKindOfClass:UIButton.class] ||
                    [v isKindOfClass:UIControl.class] ||
                    [v isKindOfClass:UIImageView.class];

    // 稳定识别：优先靠搜索相关名称；如果类名/label没有暴露，则仅允许非常靠右上角的小图标命中。
    BOOL veryCornerIcon = r.origin.x > screen.width * 0.82 &&
                          r.origin.y < screen.height * 0.13 &&
                          r.size.width <= 70 &&
                          r.size.height <= 70 &&
                          classHit;

    return textHit || veryCornerIcon;
}

static void AXApplyVisibleSettings(void) {
    UIWindow *win = AXKeyWindow();
    if (!win) return;

    CGFloat topOpacity = AXFloat(@"ax_top_opacity", 1.0);
    CGFloat rightOpacity = AXFloat(@"ax_right_opacity", 1.0);
    CGFloat rightScale = AXFloat(@"ax_right_buttons_scale", 1.0);
    CGFloat axOpacity = AXFloat(@"ax_button_opacity", 0.55);
    BOOL hideSearch = AXBool(@"ax_hide_top_search", NO);

    if (rightScale < 0.50) rightScale = 0.50;
    if (rightScale > 1.50) rightScale = 1.50;
    if (axOpacity < 0.05) axOpacity = 0.05;
    if (axOpacity > 1.00) axOpacity = 1.00;

    if (axButton) axButton.alpha = axOpacity;

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
    NSInteger count = 0;

    while (stack.count && count < 1000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        count++;

        if (v == axButton || AXIsInOurPanel(v)) continue;

        if (AXLooksLikeTopRightSearch(v)) {
            v.hidden = hideSearch;
            v.alpha = hideSearch ? 0.0 : 1.0;
            v.userInteractionEnabled = !hideSearch;
        } else if (AXLooksLikeTopTab(v)) {
            v.alpha = topOpacity;
        } else if (AXLooksLikeRightButtonItem(v)) {
            v.alpha = rightOpacity;
            v.transform = CGAffineTransformMakeScale(rightScale, rightScale);
        } else if (AXLooksLikeRightButtonLabel(v)) {
            v.alpha = rightOpacity;
            v.transform = CGAffineTransformMakeScale(rightScale, rightScale);
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
    UISlider *_axAlphaSlider;
    UISwitch *_floatSwitch;
    UISwitch *_hideSearchSwitch;
    UILabel *_topValue;
    UILabel *_rightValue;
    UILabel *_scaleValue;
    UILabel *_axAlphaValue;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    card.frame = CGRectMake(0, 0, 430, 590);
    card.center = self.view.center;
    card.layer.cornerRadius = 22;
    card.layer.masksToBounds = YES;
    [self.view addSubview:card];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, 430, 36)];
    title.text = @"AwemeX 设置 V6";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [card.contentView addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(376, 18, 36, 36);
    close.layer.cornerRadius = 18;
    close.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:30];
    close.tintColor = UIColor.whiteColor;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:close];

    [self addLabel:@"顶部不透明度" y:72 card:card];
    _topValue = [self addValueLabelY:72 card:card];
    _topSlider = [self addSliderY:102 key:@"ax_top_opacity" def:1.0 min:0.0 max:1.0 card:card];

    [self addLabel:@"右侧按钮不透明度" y:148 card:card];
    _rightValue = [self addValueLabelY:148 card:card];
    _rightSlider = [self addSliderY:178 key:@"ax_right_opacity" def:1.0 min:0.0 max:1.0 card:card];

    [self addLabel:@"右侧按钮缩放比例度" y:224 card:card];
    _scaleValue = [self addValueLabelY:224 card:card];
    _scaleSlider = [self addSliderY:254 key:@"ax_right_buttons_scale" def:1.0 min:0.5 max:1.5 card:card];

    [self addLabel:@"AX 图标不透明度" y:300 card:card];
    _axAlphaValue = [self addValueLabelY:300 card:card];
    _axAlphaSlider = [self addSliderY:330 key:@"ax_button_opacity" def:0.55 min:0.05 max:1.0 card:card];

    UILabel *searchLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 378, 250, 36)];
    searchLabel.text = @"隐藏右上搜索";
    searchLabel.textColor = UIColor.whiteColor;
    searchLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:searchLabel];

    _hideSearchSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(345, 379, 60, 36)];
    _hideSearchSwitch.on = AXBool(@"ax_hide_top_search", NO);
    [_hideSearchSwitch addTarget:self action:@selector(hideSearchChanged:) forControlEvents:UIControlEventValueChanged];
    [card.contentView addSubview:_hideSearchSwitch];

    UILabel *floatLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 426, 220, 36)];
    floatLabel.text = @"显示 AX 悬浮按钮";
    floatLabel.textColor = UIColor.whiteColor;
    floatLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:floatLabel];

    _floatSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(345, 427, 60, 36)];
    _floatSwitch.on = AXBool(@"ax_float_enabled", YES);
    [_floatSwitch addTarget:self action:@selector(floatChanged:) forControlEvents:UIControlEventValueChanged];
    [card.contentView addSubview:_floatSwitch];

    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(24, 474, 382, 36)];
    tip.text = @"搜索隐藏采用右上角位置 + 搜索关键词 + 小图标兜底识别。";
    tip.textColor = [UIColor colorWithWhite:1 alpha:0.72];
    tip.font = [UIFont systemFontOfSize:12];
    tip.numberOfLines = 2;
    [card.contentView addSubview:tip];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.frame = CGRectMake(40, 525, 350, 42);
    reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
    reset.layer.cornerRadius = 12;
    [reset setTitle:@"恢复默认" forState:UIControlStateNormal];
    reset.tintColor = UIColor.whiteColor;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:reset];

    [self updateValueLabels];
}

- (void)addLabel:(NSString *)text y:(CGFloat)y card:(UIVisualEffectView *)card {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, y, 250, 24)];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:label];
}

- (UILabel *)addValueLabelY:(CGFloat)y card:(UIVisualEffectView *)card {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(305, y, 100, 24)];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    label.textAlignment = NSTextAlignmentRight;
    label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    [card.contentView addSubview:label];
    return label;
}

- (UISlider *)addSliderY:(CGFloat)y key:(NSString *)key def:(CGFloat)def min:(CGFloat)min max:(CGFloat)max card:(UIVisualEffectView *)card {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(24, y, 382, 32)];
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
    _axAlphaValue.text = [NSString stringWithFormat:@"%.0f%%", _axAlphaSlider.value * 100.0];
}

- (void)sliderChanged:(UISlider *)sender {
    [[NSUserDefaults standardUserDefaults] setFloat:sender.value forKey:sender.accessibilityIdentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateValueLabels];
    AXApplyVisibleSettings();
}

- (void)hideSearchChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ax_hide_top_search"];
    [[NSUserDefaults standardUserDefaults] synchronize];
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
    [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_right_buttons_scale"];
    [[NSUserDefaults standardUserDefaults] setFloat:0.55 forKey:@"ax_button_opacity"];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ax_hide_top_search"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    _topSlider.value = 1.0;
    _rightSlider.value = 1.0;
    _scaleSlider.value = 1.0;
    _axAlphaSlider.value = 0.55;
    _hideSearchSwitch.on = NO;
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

        CGFloat size = 54.0;
        axButton = [UIButton buttonWithType:UIButtonTypeCustom];
        axButton.frame = CGRectMake(210, 200, size, size);
        axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        axButton.layer.cornerRadius = size / 2.0;
        axButton.layer.masksToBounds = YES;
        axButton.alpha = AXFloat(@"ax_button_opacity", 0.55);
        [axButton setTitle:@"AX" forState:UIControlStateNormal];
        axButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];

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
