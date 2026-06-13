
#import <UIKit/UIKit.h>

static UIButton *axButton = nil;

static UIViewController *AXTopVC(void) {
    UIViewController *vc = UIApplication.sharedApplication.keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

static void AXAddButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = UIApplication.sharedApplication.keyWindow;
        if (!win || axButton) return;

        axButton = [UIButton buttonWithType:UIButtonTypeCustom];
        axButton.frame = CGRectMake(200, 200, 80, 80);
        axButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
        axButton.layer.cornerRadius = 40;
        [axButton setTitle:@"AX" forState:UIControlStateNormal];

        [axButton addTarget:[UIApplication sharedApplication]
                     action:@selector(ax_openPanel)
           forControlEvents:UIControlEventTouchUpInside];

        [win addSubview:axButton];
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
    UIViewController *vc = AXTopVC();
    if (!vc) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"AwemeX"
                                                                   message:@"AX 按钮正常"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}

%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        AXAddButton();
    });
}
