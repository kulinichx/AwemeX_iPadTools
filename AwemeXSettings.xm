#import <UIKit/UIKit.h>
#import "AwemeXSettingsHelper.h"
#import "AwemeXCustomInputView.h"

@interface AwemeXSettingsViewController : UIViewController
@end

@implementation AwemeXSettingsViewController {
    UIScrollView *_scrollView;
    UIStackView *_stackView;
    NSMutableArray<AwemeXCustomInputView *> *_inputRows;
    UISwitch *_searchSwitch;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AwemeX iPad 调节";
    self.view.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    _inputRows = [NSMutableArray array];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"重置" style:UIBarButtonItemStylePlain target:self action:@selector(resetTapped)];

    _scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_scrollView];

    _stackView = [[UIStackView alloc] initWithFrame:CGRectZero];
    _stackView.axis = UILayoutConstraintAxisVertical;
    _stackView.spacing = 1;
    [_scrollView addSubview:_stackView];

    [self addHeader:@"数值为 0 时不修改原状态，拖动滑条实时生效。"];
    [self addInput:@"设置顶栏透明" key:@"awemex_topAlpha" placeholder:@"0" maxValue:1.0];
    [self addInput:@"设置全局透明" key:@"awemex_globalAlpha" placeholder:@"0" maxValue:1.0];
    [self addInput:@"首页头像透明" key:@"awemex_avatarAlpha" placeholder:@"0" maxValue:1.0];
    [self addInput:@"右侧栏缩放度" key:@"awemex_rightScale" placeholder:@"0" maxValue:1.5];
    [self addSwitch:@"隐藏右上搜索" key:@"awemex_hideTopSearch"];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadRows) name:AwemeXSettingsChangedNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat top = self.view.safeAreaInsets.top > 0 ? 12 : 8;
    _stackView.frame = CGRectMake(0, top, width, _stackView.arrangedSubviews.count * 58 + 46);
    _scrollView.contentSize = CGSizeMake(width, CGRectGetMaxY(_stackView.frame) + 24);
}

- (void)addHeader:(NSString *)text {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.textColor = [UIColor colorWithWhite:0.72 alpha:1];
    label.font = [UIFont systemFontOfSize:13];
    label.numberOfLines = 0;
    label.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [_stackView addArrangedSubview:label];
    [label.heightAnchor constraintEqualToConstant:46].active = YES;
}

- (void)addInput:(NSString *)title key:(NSString *)key placeholder:(NSString *)placeholder maxValue:(CGFloat)maxValue {
    AwemeXCustomInputView *row = [[AwemeXCustomInputView alloc] initWithTitle:title key:key placeholder:placeholder maxValue:maxValue];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [_stackView addArrangedSubview:row];
    [row.heightAnchor constraintEqualToConstant:58].active = YES;
    [_inputRows addObject:row];
}

- (void)addSwitch:(NSString *)title key:(NSString *)key {
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = title;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:16];
    [row addSubview:label];

    _searchSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    _searchSwitch.on = [[AwemeXSettingsHelper shared] hideTopSearch];
    _searchSwitch.accessibilityIdentifier = key;
    [_searchSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:_searchSwitch];

    label.translatesAutoresizingMaskIntoConstraints = NO;
    _searchSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [_searchSwitch.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16],
        [_searchSwitch.centerYAnchor constraintEqualToAnchor:row.centerYAnchor]
    ]];

    [_stackView addArrangedSubview:row];
    [row.heightAnchor constraintEqualToConstant:58].active = YES;
}

- (void)switchChanged:(UISwitch *)sender {
    [[AwemeXSettingsHelper shared] setBool:sender.on forKey:sender.accessibilityIdentifier];
}

- (void)reloadRows {
    for (AwemeXCustomInputView *row in _inputRows) [row reloadValue];
    _searchSwitch.on = [[AwemeXSettingsHelper shared] hideTopSearch];
}

- (void)resetTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重置调节参数" message:@"所有数值会恢复为 0，隐藏搜索恢复关闭。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重置" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [[AwemeXSettingsHelper shared] resetAll];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

extern "C" void AwemeXPresentSettingsFromViewController(UIViewController *vc) {
    if (!vc) return;
    AwemeXSettingsViewController *settings = [AwemeXSettingsViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;
    [vc presentViewController:nav animated:YES completion:nil];
}
