#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface AWEElementStackView : UIView
@end

static UIButton *axButton;
static UIView *axPanel;
static UILabel *axScaleValueLabel;
static UILabel *axButtonAlphaValueLabel;
static UISwitch *axButtonSwitch;

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
    for (UIWindow *w in app.windows) {
        if (w.isKeyWindow) return w;
    }
    return app.windows.firstObject;
}

static CGFloat AXFloat(NSString *key, CGFloat def) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return obj ? [obj floatValue] : def;
}

static BOOL AXBool(NSString *key, BOOL def) {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return obj ? [obj boolValue] : def;
}

static void AXSaveFloat(NSString *key, CGFloat value) {
    [[NSUserDefaults standardUserDefaults] setObject:@(value) forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static void AXSaveBool(NSString *key, BOOL value) {
    [[NSUserDefaults standardUserDefaults] setObject:@(value) forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static BOOL AXIsRightStack(UIView *v){
    if(![v isKindOfClass:NSClassFromString(@"AWEElementStackView")]) return NO;
    NSString *label = v.accessibilityLabel;
    return [label isEqualToString:@"right"] || CGRectGetMinX(v.frame) > UIScreen.mainScreen.bounds.size.width * 0.55;
}

static void AXApplyScale(UIView *v){
    if(!AXIsRightStack(v)) return;
    CGFloat scale = AXFloat(@"ax_scale", 0.81);
    CGFloat rightAlpha = AXFloat(@"ax_right_alpha", 0.80);
    v.transform = CGAffineTransformMakeScale(scale, scale);
    v.alpha = rightAlpha;
}

static UILabel *AXLabel(UIView *parent, NSString *text, CGFloat x, CGFloat y, CGFloat w, CGFloat h, CGFloat fontSize, NSTextAlignment align) {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, h)];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:fontSize];
    label.textAlignment = align;
    [parent addSubview:label];
    return label;
}

@interface AXMenuTarget : NSObject
+ (instancetype)shared;
- (void)openSettings;
- (void)closeSettings;
- (void)scaleChanged:(UISlider *)slider;
- (void)buttonAlphaChanged:(UISlider *)slider;
- (void)showButtonChanged:(UISwitch *)sender;
- (void)resetDefaults;
@end

@implementation AXMenuTarget
+ (instancetype)shared {
    static AXMenuTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ target = [AXMenuTarget new]; });
    return target;
}

- (void)refreshButton {
    BOOL show = AXBool(@"ax_show_button", YES);
    CGFloat alpha = AXFloat(@"ax_button_alpha", 0.34);
    axButton.hidden = !show;
    axButton.alpha = alpha;
    if (axButtonSwitch) axButtonSwitch.on = show;
}

- (void)refreshLayout {
    UIWindow *w = AXKeyWindow();
    for (UIView *v in w.subviews) {
        [v setNeedsLayout];
        [v layoutIfNeeded];
    }
}

- (void)scaleChanged:(UISlider *)slider {
    CGFloat value = round(slider.value * 100.0) / 100.0;
    AXSaveFloat(@"ax_scale", value);
    axScaleValueLabel.text = [NSString stringWithFormat:@"%.2fx", value];
    [self refreshLayout];
}

- (void)buttonAlphaChanged:(UISlider *)slider {
    CGFloat value = round(slider.value * 100.0) / 100.0;
    AXSaveFloat(@"ax_button_alpha", value);
    axButtonAlphaValueLabel.text = [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    [self refreshButton];
}

- (void)showButtonChanged:(UISwitch *)sender {
    AXSaveBool(@"ax_show_button", sender.on);
    [self refreshButton];
}

- (void)resetDefaults {
    AXSaveFloat(@"ax_scale", 0.81);
    AXSaveFloat(@"ax_right_alpha", 0.80);
    AXSaveFloat(@"ax_button_alpha", 0.34);
    AXSaveBool(@"ax_show_button", YES);
    [self closeSettings];
    [self openSettings];
    [self refreshLayout];
    [self refreshButton];
}

- (void)closeSettings {
    [axPanel removeFromSuperview];
    axPanel = nil;
    axScaleValueLabel = nil;
    axButtonAlphaValueLabel = nil;
    axButtonSwitch = nil;
}

- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXKeyWindow();
        if (!w) return;
        if (axPanel) { [self closeSettings]; return; }

        UIView *dim = [[UIView alloc] initWithFrame:w.bounds];
        dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
        axPanel = dim;
        [w addSubview:dim];

        CGFloat pw = MIN(520.0, w.bounds.size.width - 80.0);
        CGFloat ph = 430.0;
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake((w.bounds.size.width - pw) / 2.0, (w.bounds.size.height - ph) / 2.0, pw, ph)];
        card.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        card.backgroundColor = [[UIColor colorWithWhite:0.08 alpha:1.0] colorWithAlphaComponent:0.82];
        card.layer.cornerRadius = 18.0;
        card.clipsToBounds = YES;
        [dim addSubview:card];

        AXLabel(card, @"AwemeX 设置 V7", 0, 22, pw, 26, 18, NSTextAlignmentCenter);
        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(pw - 54, 18, 36, 36);
        close.layer.cornerRadius = 18;
        close.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
        [close setTitle:@"×" forState:UIControlStateNormal];
        [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont systemFontOfSize:25 weight:UIFontWeightRegular];
        [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:close];

        CGFloat left = 32.0;
        CGFloat right = pw - 34.0;
        CGFloat labelW = pw - 64.0;
        CGFloat y = 76.0;

        AXLabel(card, @"右侧按钮缩放比例度", left, y, labelW - 72, 26, 16, NSTextAlignmentLeft);
        axScaleValueLabel = AXLabel(card, @"", right - 90, y, 90, 26, 15, NSTextAlignmentRight);
        UISlider *scale = [[UISlider alloc] initWithFrame:CGRectMake(left, y + 42, labelW, 28)];
        scale.minimumValue = 0.70;
        scale.maximumValue = 1.20;
        scale.value = AXFloat(@"ax_scale", 0.81);
        [scale addTarget:self action:@selector(scaleChanged:) forControlEvents:UIControlEventValueChanged];
        [card addSubview:scale];
        [self scaleChanged:scale];

        y += 92.0;
        AXLabel(card, @"AX 图标不透明度", left, y, labelW - 72, 26, 16, NSTextAlignmentLeft);
        axButtonAlphaValueLabel = AXLabel(card, @"", right - 90, y, 90, 26, 15, NSTextAlignmentRight);
        UISlider *alpha = [[UISlider alloc] initWithFrame:CGRectMake(left, y + 42, labelW, 28)];
        alpha.minimumValue = 0.05;
        alpha.maximumValue = 1.00;
        alpha.value = AXFloat(@"ax_button_alpha", 0.34);
        [alpha addTarget:self action:@selector(buttonAlphaChanged:) forControlEvents:UIControlEventValueChanged];
        [card addSubview:alpha];
        [self buttonAlphaChanged:alpha];

        y += 96.0;
        AXLabel(card, @"显示 AX 悬浮按钮", left, y, labelW - 80, 32, 16, NSTextAlignmentLeft);
        axButtonSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(right - 54, y - 1, 54, 32)];
        axButtonSwitch.on = AXBool(@"ax_show_button", YES);
        [axButtonSwitch addTarget:self action:@selector(showButtonChanged:) forControlEvents:UIControlEventValueChanged];
        [card addSubview:axButtonSwitch];

        UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(left, y + 54, labelW, 42)];
        hint.text = @"V7 修复版：恢复深色设置面板；右侧按钮缩放改为右下锚点，滑动或重新进入视频页生效。";
        hint.textColor = [UIColor colorWithWhite:1.0 alpha:0.62];
        hint.font = [UIFont systemFontOfSize:13];
        hint.numberOfLines = 2;
        [card addSubview:hint];

        UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
        reset.frame = CGRectMake(left + 20, ph - 66, labelW - 40, 44);
        reset.layer.cornerRadius = 11;
        reset.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
        [reset setTitle:@"恢复默认" forState:UIControlStateNormal];
        [reset setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        reset.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        [reset addTarget:self action:@selector(resetDefaults) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:reset];
    });
}
@end

static void AXShow(void){
    UIWindow *w = AXKeyWindow();
    if(!w) return;
    if(axButton) {
        if (axButton.superview != w) [w addSubview:axButton];
        [[AXMenuTarget shared] refreshButton];
        return;
    }
    axButton = [UIButton buttonWithType:UIButtonTypeSystem];
    axButton.frame = CGRectMake(20,200,44,44);
    axButton.layer.cornerRadius = 22;
    axButton.clipsToBounds = YES;
    axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.70];
    [axButton setTitle:@"AX" forState:UIControlStateNormal];
    [axButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [axButton addTarget:[AXMenuTarget shared] action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:axButton];
    [[AXMenuTarget shared] refreshButton];
}

%hook AWEElementStackView
- (void)layoutSubviews{
    %orig;
    AXApplyScale((UIView *)self);
}
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app{
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{ AXShow(); });
}
%end

%ctor{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{ AXShow(); });
}
