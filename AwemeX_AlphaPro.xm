#import <UIKit/UIKit.h>

static UIButton *axButton = nil;

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

@interface AXSettingsViewController : UIViewController
@end

@implementation AXSettingsViewController {
    UISlider *_topSlider;
    UISlider *_rightSlider;
    UISwitch *_floatSwitch;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    card.frame = CGRectMake(0, 0, 380, 360);
    card.center = self.view.center;
    card.layer.cornerRadius = 22;
    card.layer.masksToBounds = YES;
    [self.view addSubview:card];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, 380, 36)];
    title.text = @"AwemeX 设置";
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:18];
    [card.contentView addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(326, 18, 36, 36);
    close.layer.cornerRadius = 18;
    close.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:30];
    close.tintColor = UIColor.whiteColor;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:close];

    [self addLabel:@"顶部透明度" y:82 card:card];
    _topSlider = [self addSliderY:112 key:@"ax_top_alpha" def:1.0 card:card];

    [self addLabel:@"右侧面板透明度" y:158 card:card];
    _rightSlider = [self addSliderY:188 key:@"ax_right_alpha" def:1.0 card:card];

    UILabel *floatLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, 245, 220, 36)];
    floatLabel.text = @"显示 AX 悬浮按钮";
    floatLabel.textColor = UIColor.whiteColor;
    floatLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:floatLabel];

    _floatSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(300, 246, 60, 36)];
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:@"ax_float_enabled"];
    _floatSwitch.on = obj ? [[NSUserDefaults standardUserDefaults] boolForKey:@"ax_float_enabled"] : YES;
    [_floatSwitch addTarget:self action:@selector(floatChanged:) forControlEvents:UIControlEventValueChanged];
    [card.contentView addSubview:_floatSwitch];

    UIButton *test = [UIButton buttonWithType:UIButtonTypeSystem];
    test.frame = CGRectMake(40, 300, 300, 42);
    test.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
    test.layer.cornerRadius = 12;
    [test setTitle:@"测试：设置面板正常" forState:UIControlStateNormal];
    test.tintColor = UIColor.whiteColor;
    [test addTarget:self action:@selector(testAlert) forControlEvents:UIControlEventTouchUpInside];
    [card.contentView addSubview:test];
}

- (void)addLabel:(NSString *)text y:(CGFloat)y card:(UIVisualEffectView *)card {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24, y, 220, 24)];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [card.contentView addSubview:label];
}

- (UISlider *)addSliderY:(CGFloat)y key:(NSString *)key def:(CGFloat)def card:(UIVisualEffectView *)card {
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(24, y, 332, 32)];
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    slider.value = obj ? [[NSUserDefaults standardUserDefaults] floatForKey:key] : def;
    slider.minimumValue = 0.0;
    slider.maximumValue = 1.0;
    slider.accessibilityIdentifier = key;
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [card.contentView addSubview:slider];
    return slider;
}

- (void)sliderChanged:(UISlider *)sender {
    [[NSUserDefaults standardUserDefaults] setFloat:sender.value forKey:sender.accessibilityIdentifier];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)floatChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ax_float_enabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (axButton) axButton.hidden = !sender.on;
}

- (void)testAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AwemeX"
                                                                   message:@"设置面板正常 ✅"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
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

        id obj = [[NSUserDefaults standardUserDefaults] objectForKey:@"ax_float_enabled"];
        BOOL show = obj ? [[NSUserDefaults standardUserDefaults] boolForKey:@"ax_float_enabled"] : YES;
        axButton.hidden = !show;

        [win addSubview:axButton];
        [win bringSubviewToFront:axButton];
    });
}

%hook UIApplication

- (void)applicationDidBecomeActive:(UIApplication *)application {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AXAddButton();
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
    });
}
