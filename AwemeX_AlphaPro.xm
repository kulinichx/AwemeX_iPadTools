#import <UIKit/UIKit.h>

@interface AwemeXButton : UIButton
@end

@implementation AwemeXButton

- (instancetype)init {
    self = [super initWithFrame:CGRectMake(100, 200, 50, 50)];
    if (self) {
        self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
        self.layer.cornerRadius = 25;
        [self setTitle:@"AX" forState:UIControlStateNormal];
        [self addTarget:self action:@selector(openPanel) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)openPanel {
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) {
        vc = vc.presentedViewController;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AwemeX"
                                                                   message:@"注入成功 ✅"
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

    [vc presentViewController:alert animated:YES completion:nil];
}

@end


%hook UIWindow

- (void)didMoveToWindow {
    %orig;

    static BOOL added = NO;
    if (added) return;

    added = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AwemeXButton *btn = [[AwemeXButton alloc] init];
        [self addSubview:btn];
    });
}

%end
