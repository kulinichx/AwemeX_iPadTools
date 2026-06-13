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
    for (UIWindow *w in app.windows) return w;
    return nil;
}

static void AXShow(void){
    UIWindow *w = AXKeyWindow();
    if(!w) return;
    if(axButton) return;
    axButton = [UIButton buttonWithType:UIButtonTypeSystem];
    axButton.frame = CGRectMake(20,200,44,44);
    axButton.layer.cornerRadius = 22;
    axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    [axButton setTitle:@"AX" forState:0];
    [w addSubview:axButton];
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

%hook AWEElementStackView
- (void)layoutSubviews{
    %orig;
    AXApplyScale((UIView *)self);
}
%end

%hook UIView
- (void)setAlpha:(CGFloat)a{
    %orig;
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
