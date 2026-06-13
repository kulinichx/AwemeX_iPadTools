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
    if ([v respondsToSelector:@selector(accessibilityLabel)] && v.accessibilityLabel.length) [s appendFormat:@" %@", v.accessibilityLabel];
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
           [s containsString:@"feed"] ||
           [s containsString:@"顶部"] ||
           [s containsString:@"推荐"] ||
           [s containsString:@"关注"];
}

static BOOL AXLooksLikeRightAction(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;
    BOOL pos = r.origin.x > screen.width * 0.68;
    BOOL size = r.size.width >= 28 && r.size.width <= 160 && r.size.height >= 40 && r.size.height <= screen.height * 0.85;
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

static void AXApplyAlphaToVisibleViews(void) {
    UIWindow *win = AXKeyWindow();
    if (!win) return;

    CGFloat topAlpha = AXFloat(@"ax_top_alpha", 1.0);
    CGFloat rightAlpha = AXFloat(@"ax_right_alpha", 1.0);

    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
    NSInteger count = 0;

    while (stack.count && count < 600) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        count++;

        if (v == axButton || AXIsInOurPanel(v)) {
            continue;
        }

        if (AXLooksLikeTopTab(v)) {
            v.alpha = topAlpha;
        } else if (AXLooksLikeRightAction(v)) {
            v.alpha = rightAlpha;
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
    UISwitch *_floatSwitch;
    UILabel *_topValue;
    UILabel *_rightValue;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    card.frame = CGRectMake(0, 0, 400, 390);
    card.center = self.view.center;
    card.layer.cornerRadius = 22;
    card.layer.masksToBounds = YES;
    [self.view addSubview:card];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, 400, 36)];
    title.text = @"AwemeX 设置 V3";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [card.contentView addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(346, 18, 36, 36);
    close.layer.cornerRadius = 18;
    close.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:30];
    close.tintColor = UIColor.whiteColor;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:close];

    [self addLabel:@"顶部透明度" y:82 card:card];
    _topValue = [self addValueLabelY:82 card:card];
    _topSlider = [self addSliderY:112 key:@"ax_top_alpha" def:1.0 card:card];

    [self addLabel:@"右侧按钮透明度" y:158 card:card];
    _rightValue = [self addValueLabelY:158 card:card];
    _rightSlider = [self addSliderY:188 key:@"ax_right_alpha" def:1.0 card:card];

    UILabel *tip = [[UILabel alloc] initWithFrame:CGRectMake(24, 228, 352, 38)];
    tip.text = @"说明：本版只做安全识别，若没变化再继续按你的抖音版本精确匹配类名。";
    tip.textColor = [UIColor colorWithWhite:1 alpha:0.72];
    tip.font = [UIFont systemFontOfSize:12];
    tip.numberOfLines = 2;
    [card.contentView addSubview:tip];

    UILabel *floatLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 275, 220, 36)];
    floatLabel.text = @"显示 AX 悬浮按钮";
    floatLabel.textColor = UIColor.whiteColor;
    floatLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:floatLabel];

    _floatSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(315, 276, 60, 36)];
    _floatSwitch.on = AXBool(@"ax_float_enabled", YES);
    [_floatSwitch addTarget:self action:@selector(floatChanged:) forControlEvents:UIControlEventValueChanged];
    [card.contentView addSubview:_floatSwitch];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    reset.frame = CGRectMake(40, 330, 320, 42);
    reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
    reset.layer.cornerRadius = 12;
    [reset setTitle:@"恢复默认透明度" forState:UIControlStateNormal];
    reset.tintColor = UIColor.whiteColor;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:reset];

    [self updateValueLabels];
}

- (void)addLabel:(NSString *)text y:(CGFloat)y card:(UIVisualEffectView *)card {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, y, 220, 24)];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:label];
}

- (UILabel *)addValueLabelY:(CGFloat)y card:(UIVisualEffectView *)card {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(300, y, 72, 24)];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    label.textAlignment = NSTextAlignmentRight;
    label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    [card.contentView addSubview:label];
    return label;
}

- (UISlider *)addSliderY:(CGFloat)y key:(NSString *)key def:(CGFloat)def card:(UIVisualEffectView *)card {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(24, y, 352, 32)];
    slider.value = AXFloat(key, def);
    slider.minimumValue = 0.0;
    slider.maximumValue = 1.0;
    slider.accessibilityIdentifier = key;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card.contentView addSubview:slider];
    return slider;
}

- (void)updateValueLabels {
    _topValue.text = [NSString stringWithFormat:@"%.2f", _topSlider.value];
    _rightValue.text = [NSString stringWithFormat:@"%.2f", _rightSlider.value];
}

- (void)sliderChanged:(UISlider *)sender {
    [[NSUserDefaults standardUserDefaults] setFloat:sender.value forKey:sender.accessibilityIdentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self updateValueLabels];
    AXApplyAlphaToVisibleViews();
}

- (void)floatChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ax_float_enabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (axButton) axButton.hidden = !sender.on;
}

- (void)resetTapped {
    [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_top_alpha"];
    [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_right_alpha"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    _topSlider.value = 1.0;
    _rightSlider.value = 1.0;
    [self updateValueLabels];
    AXApplyAlphaToVisibleViews();
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
                AXApplyAlphaToVisibleViews();
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
        AXApplyAlphaToVisibleViews();
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
        AXApplyAlphaToVisibleViews();
    });
}
