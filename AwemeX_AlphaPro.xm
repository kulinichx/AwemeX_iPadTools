#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface AWEElementStackView : UIView
@end

static UIButton *axButton;

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

static UIViewController *AXTopViewController(void) {
    UIWindow *w = AXKeyWindow();
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) vc = ((UINavigationController *)vc).topViewController;
    if ([vc isKindOfClass:UITabBarController.class]) vc = ((UITabBarController *)vc).selectedViewController;
    return vc;
}

static BOOL AXIsRightStack(UIView *v){
    if(![v isKindOfClass:NSClassFromString(@"AWEElementStackView")]) return NO;
    NSString *label = v.accessibilityLabel;
    return [label isEqualToString:@"right"];
}

static void AXApplyScale(UIView *v){
    if(!AXIsRightStack(v)) return;
    CGFloat scale = 1.0;
    NSNumber *s = [[NSUserDefaults standardUserDefaults] objectForKey:@"ax_scale"];
    if(s) scale = s.floatValue;
    v.transform = CGAffineTransformMakeScale(scale, scale);
}

@interface AXMenuTarget : NSObject
+ (instancetype)shared;
- (void)openSettings;
@end

@implementation AXMenuTarget
+ (instancetype)shared {
    static AXMenuTarget *target;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [AXMenuTarget new];
    });
    return target;
}

- (void)setScale:(CGFloat)scale {
    [[NSUserDefaults standardUserDefaults] setObject:@(scale) forKey:@"ax_scale"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    UIWindow *w = AXKeyWindow();
    for (UIView *v in w.subviews) {
        [v setNeedsLayout];
        [v layoutIfNeeded];
    }
}

- (void)openSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = AXTopViewController();
        if (!vc) return;
        if (vc.presentedViewController) return;

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AwemeX"
                                                                       message:@"选择右侧按钮缩放比例，设置后重新进入视频页或滑动一下即可生效。"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
        NSArray<NSNumber *> *values = @[@0.80, @0.90, @1.00, @1.10, @1.20];
        for (NSNumber *num in values) {
            NSString *title = [NSString stringWithFormat:@"%.0f%%", num.floatValue * 100.0];
            [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                [self setScale:num.floatValue];
            }]];
        }
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

        UIPopoverPresentationController *pop = alert.popoverPresentationController;
        if (pop) {
            pop.sourceView = axButton ?: vc.view;
            pop.sourceRect = (axButton ? axButton.bounds : vc.view.bounds);
            pop.permittedArrowDirections = UIPopoverArrowDirectionAny;
        }
        [vc presentViewController:alert animated:YES completion:nil];
    });
}
@end

static void AXShow(void){
    UIWindow *w = AXKeyWindow();
    if(!w) return;
    if(axButton) {
        if (axButton.superview != w) [w addSubview:axButton];
        return;
    }
    axButton = [UIButton buttonWithType:UIButtonTypeSystem];
    axButton.frame = CGRectMake(20,200,44,44);
    axButton.layer.cornerRadius = 22;
    axButton.clipsToBounds = YES;
    axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    [axButton setTitle:@"AX" forState:UIControlStateNormal];
    [axButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [axButton addTarget:[AXMenuTarget shared] action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [w addSubview:axButton];
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        AXShow();
    });
}
%end

%ctor{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        AXShow();
    });
}
