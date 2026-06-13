#import <UIKit/UIKit.h>
#import "AwemeXSettingsHelper.h"
#import "AwemeXCustomInputView.h"

@interface AwemeXSectionHeader : UIControl
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) UILabel *arrow;
@property(nonatomic, strong) UIStackView *body;
@end

@implementation AwemeXSectionHeader
@end

@interface AwemeXSettingsViewController : UIViewController
@end

@implementation AwemeXSettingsViewController {
    UIVisualEffectView *_blurCard;
    UIScrollView *_scroll;
    UIStackView *_stack;
    NSMutableArray<AwemeXCustomInputView *> *_rows;
    NSMutableDictionary<NSString *, UISwitch *> *_switches;
    NSMutableArray<AwemeXSectionHeader *> *_sections;
    UIStackView *_currentBody;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
    _rows = [NSMutableArray array];
    _switches = [NSMutableDictionary dictionary];
    _sections = [NSMutableArray array];

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    _blurCard = [[UIVisualEffectView alloc] initWithEffect:effect];
    _blurCard.layer.cornerRadius = 22;
    _blurCard.layer.masksToBounds = YES;
    _blurCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_blurCard];

    UIView *content = _blurCard.contentView;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"AwemeX";
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:17];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"×" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightLight];
    close.tintColor = UIColor.whiteColor;
    close.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.22];
    close.layer.cornerRadius = 19;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:close];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"↺" forState:UIControlStateNormal];
    reset.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightRegular];
    reset.tintColor = UIColor.whiteColor;
    reset.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.22];
    reset.layer.cornerRadius = 19;
    reset.translatesAutoresizingMaskIntoConstraints = NO;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [content addSubview:reset];

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:_scroll];

    _stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 8;
    _stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_stack];

    [self addSection:@"界面透明" expanded:YES];
    [self addInput:@"顶部透明度" subtitle:@"精选/关注/推荐" key:@"awemex_topAlpha" min:0 max:1 def:1];
    [self addInput:@"右侧数值透明度" subtitle:@"点赞/评论/分享数字" key:@"awemex_rightAlpha" min:0 max:1 def:1];
    [self addInput:@"点赞爱心等透明度" subtitle:@"右侧操作图标" key:@"awemex_likeAlpha" min:0 max:1 def:1];
    [self addInput:@"整体头像透明度" subtitle:@"右侧头像" key:@"awemex_avatarAlpha" min:0 max:1 def:1];
    [self addInput:@"底部文字透明度" subtitle:@"标题、文案、发布时间、IP" key:@"awemex_bottomTextAlpha" min:0 max:1 def:1];
    [self addInput:@"音乐圆角图标透明度" subtitle:@"底部音乐/圆角图标" key:@"awemex_musicAlpha" min:0 max:1 def:1];

    [self addSection:@"播放面板布局" expanded:YES];
    [self addInput:@"右侧播放面板缩放" subtitle:@"只缩放播放页右侧头像/点赞/评论/分享，不影响设置/我的/消息等界面" key:@"awemex_rightScale" min:0.50 max:1.50 def:1];

    [self addSection:@"面板设置" expanded:NO];
    [self addSwitch:@"启用新版长按面板" key:@"awemex_newLongPressPanel" defaultOn:YES];
    [self addSwitch:@"长按面板玻璃效果" key:@"awemex_longPressPanelGlass" defaultOn:NO];
    [self addSwitch:@"长按面板深色模式" key:@"awemex_longPressPanelDarkMode" defaultOn:NO];
    [self addSwitch:@"保存面板玻璃效果" key:@"awemex_savePanelGlass" defaultOn:NO];
    [self addInput:@"面板毛玻璃透明度" subtitle:@"0-1 小数" key:@"awemex_panelGlassAlpha" min:0 max:1 def:0.65];

    [self addSection:@"长按面板功能" expanded:NO];
    [self addSwitch:@"长按面板保存视频" key:@"awemex_longPressSaveVideo" defaultOn:YES];
    [self addSwitch:@"长按面板保存封面" key:@"awemex_longPressSaveCover" defaultOn:YES];
    [self addSwitch:@"长按面板保存音频" key:@"awemex_longPressSaveAudio" defaultOn:YES];
    [self addSwitch:@"长按面板保存图片" key:@"awemex_longPressSaveImage" defaultOn:YES];
    [self addSwitch:@"长按保存所有图片" key:@"awemex_longPressSaveAllImages" defaultOn:YES];
    [self addSwitch:@"长按面板生成视频" key:@"awemex_longPressGenerateVideo" defaultOn:NO];
    [self addSwitch:@"长按面板复制文案" key:@"awemex_longPressCopyText" defaultOn:NO];

    [self addSection:@"入口" expanded:YES];
    [self addSwitch:@"隐藏右上搜索" key:@"awemex_hideTopSearch" defaultOn:NO];
    [self addSwitch:@"显示 AX 悬浮按钮" key:@"awemex_floatingButton" defaultOn:YES];

    [NSLayoutConstraint activateConstraints:@[
        [_blurCard.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_blurCard.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_blurCard.widthAnchor constraintEqualToConstant:470],
        [_blurCard.heightAnchor constraintLessThanOrEqualToAnchor:self.view.heightAnchor multiplier:0.86],

        [title.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [title.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [title.heightAnchor constraintEqualToConstant:34],

        [reset.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [reset.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [reset.widthAnchor constraintEqualToConstant:38],
        [reset.heightAnchor constraintEqualToConstant:38],

        [close.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.widthAnchor constraintEqualToConstant:38],
        [close.heightAnchor constraintEqualToConstant:38],

        [_scroll.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [_scroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [_scroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
        [_scroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-18],

        [_stack.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor],
        [_stack.leadingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.leadingAnchor],
        [_stack.trailingAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.trailingAnchor],
        [_stack.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor],
        [_stack.widthAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.widthAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadRows) name:AwemeXSettingsChangedNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)addSection:(NSString *)text expanded:(BOOL)expanded {
    AwemeXSectionHeader *header = [[AwemeXSectionHeader alloc] initWithFrame:CGRectZero];
    header.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25];
    header.layer.cornerRadius = 10;
    header.layer.masksToBounds = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = [NSString stringWithFormat:@"  %@", text];
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:15];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:label];

    UILabel *arrow = [[UILabel alloc] initWithFrame:CGRectZero];
    arrow.text = expanded ? @"⌃" : @"⌄";
    arrow.textColor = [UIColor colorWithWhite:1 alpha:0.75];
    arrow.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
    arrow.textAlignment = NSTextAlignmentCenter;
    arrow.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:arrow];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:6],
        [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [arrow.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-12],
        [arrow.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [arrow.widthAnchor constraintEqualToConstant:34],
    ]];

    UIStackView *body = [[UIStackView alloc] initWithFrame:CGRectZero];
    body.axis = UILayoutConstraintAxisVertical;
    body.spacing = 6;
    body.hidden = !expanded;

    header.label = label;
    header.arrow = arrow;
    header.body = body;
    [header addTarget:self action:@selector(toggleSection:) forControlEvents:UIControlEventTouchUpInside];

    [_stack addArrangedSubview:header];
    [header.heightAnchor constraintEqualToConstant:38].active = YES;
    [_stack addArrangedSubview:body];

    _currentBody = body;
    [_sections addObject:header];
}

- (void)toggleSection:(AwemeXSectionHeader *)header {
    header.body.hidden = !header.body.hidden;
    header.arrow.text = header.body.hidden ? @"⌄" : @"⌃";
    [UIView animateWithDuration:0.20 animations:^{
        [self.view layoutIfNeeded];
    }];
}

- (void)addInput:(NSString *)title subtitle:(NSString *)subtitle key:(NSString *)key min:(CGFloat)min max:(CGFloat)max def:(CGFloat)def {
    AwemeXCustomInputView *row = [[AwemeXCustomInputView alloc] initWithTitle:title subtitle:subtitle key:key minValue:min maxValue:max defaultValue:def valueFormat:@"%.2f"];
    row.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.10];
    row.layer.cornerRadius = 10;
    row.layer.masksToBounds = YES;
    [_currentBody addArrangedSubview:row];
    [row.heightAnchor constraintEqualToConstant:76].active = YES;
    [_rows addObject:row];
}

- (void)addSwitch:(NSString *)title key:(NSString *)key defaultOn:(BOOL)defaultOn {
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.10];
    row.layer.cornerRadius = 10;
    row.layer.masksToBounds = YES;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = title;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:14];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
    sw.accessibilityIdentifier = key;
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    sw.on = obj ? [[NSUserDefaults standardUserDefaults] boolForKey:key] : defaultOn;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    sw.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:sw];

    _switches[key] = sw;

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:14],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [sw.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-14],
        [sw.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];

    [_currentBody addArrangedSubview:row];
    [row.heightAnchor constraintEqualToConstant:52].active = YES;
}

- (void)switchChanged:(UISwitch *)sender {
    [[AwemeXSettingsHelper shared] setBool:sender.on forKey:sender.accessibilityIdentifier];
}

- (void)reloadRows {
    for (AwemeXCustomInputView *row in _rows) [row reloadValue];
    [_switches enumerateKeysAndObjectsUsingBlock:^(NSString *key, UISwitch *sw, BOOL *stop) {
        id obj = [[NSUserDefaults standardUserDefaults] objectForKey:key];
        if (obj) sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:key];
    }];
}

- (void)resetTapped {
    [[AwemeXSettingsHelper shared] resetAll];
    [self reloadRows];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

extern "C" void AwemeXPresentSettingsFromViewController(UIViewController *vc) {
    if (!vc) return;
    AwemeXSettingsViewController *settings = [AwemeXSettingsViewController new];
    settings.modalPresentationStyle = UIModalPresentationOverFullScreen;
    settings.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [vc presentViewController:settings animated:YES completion:nil];
}
