#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <math.h>

static UIButton *axButton = nil;
static NSTimer *axTimer = nil;
static __weak UIView *axPanelRoot = nil;
static __weak UIView *axRightScaledContainer = nil;
static const char kAXRightContainerAnchorAdjustedKey;

static UIWindow *AXKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in windowScene.windows) if (w.isKeyWindow) return w;
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
    if ([v isKindOfClass:UILabel.class]) { NSString *t=((UILabel *)v).text; if(t.length)[s appendFormat:@" %@",t]; }
    if ([v isKindOfClass:UITextField.class]) { UITextField *tf=(UITextField *)v; if(tf.text.length)[s appendFormat:@" %@",tf.text]; if(tf.placeholder.length)[s appendFormat:@" %@",tf.placeholder]; }
    return s.lowercaseString;
}

static NSString *AXDeepInfo(UIView *v, NSInteger depth) {
    NSMutableString *s = [NSMutableString stringWithString:AXInfo(v)];
    if (depth <= 0) return s;
    for (UIView *sub in v.subviews) [s appendFormat:@" %@", AXDeepInfo(sub, depth - 1)];
    return s.lowercaseString;
}

static BOOL AXIsInOurPanel(UIView *v) {
    UIView *cur = v;
    while (cur) {
        if (cur == axPanelRoot) return YES;
        if (cur == axButton) return YES;
        if ([cur.accessibilityIdentifier hasPrefix:@"AXSettings"]) return YES;
        if ([NSStringFromClass(cur.class) containsString:@"AXSettings"]) return YES;
        cur = cur.superview;
    }
    return NO;
}

static BOOL AXLooksLikeTopTab(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    CGRect r=[v.superview convertRect:v.frame toView:nil]; CGSize screen=UIScreen.mainScreen.bounds.size;
    if (r.origin.y > screen.height * 0.18) return NO;
    if (r.size.height < 20 || r.size.height > 90) return NO;
    NSString *s=AXInfo(v);
    return [s containsString:@"tab"] || [s containsString:@"channel"] || [s containsString:@"顶部"] || [s containsString:@"推荐"] || [s containsString:@"关注"];
}

static BOOL AXLooksLikeRightButtonItem(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    if (v.hidden || v.alpha <= 0.01) return NO;
    CGRect r=[v.superview convertRect:v.frame toView:nil]; CGSize screen=UIScreen.mainScreen.bounds.size;

    // V8 关键修复：只处理播放页右侧下半区纵列按钮，避免误伤顶部推荐/关注按钮、右上关闭按钮、设置面板按钮。
    BOOL rightColumn = r.origin.x > screen.width * 0.80;
    BOOL playbackZone = r.origin.y > screen.height * 0.45 && r.origin.y < screen.height * 0.92;
    BOOL itemSize = r.size.width >= 18 && r.size.width <= 120 && r.size.height >= 18 && r.size.height <= 145;
    if (!(rightColumn && playbackZone && itemSize)) return NO;

    NSString *s=AXInfo(v);
    BOOL nameHit=[s containsString:@"digg"] || [s containsString:@"like"] || [s containsString:@"comment"] || [s containsString:@"collect"] || [s containsString:@"favorite"] || [s containsString:@"share"] || [s containsString:@"avatar"] || [s containsString:@"follow"] || [s containsString:@"action"];
    BOOL imageLike=[v isKindOfClass:UIImageView.class] || [v isKindOfClass:UIButton.class] || [v isKindOfClass:UIControl.class];
    BOOL compactLeaf=v.subviews.count <= 4;
    return nameHit || (imageLike && compactLeaf);
}

static BOOL AXLooksLikeRightButtonLabel(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    if (![v isKindOfClass:UILabel.class]) return NO;
    CGRect r=[v.superview convertRect:v.frame toView:nil]; CGSize screen=UIScreen.mainScreen.bounds.size;
    BOOL rightColumn = r.origin.x > screen.width * 0.80;
    BOOL playbackZone = r.origin.y > screen.height * 0.45 && r.origin.y < screen.height * 0.94;
    BOOL labelSize = r.size.width >= 8 && r.size.width <= 120 && r.size.height >= 8 && r.size.height <= 55;
    return rightColumn && playbackZone && labelSize;
}

static BOOL AXLooksLikeTopRightSearch(UIView *v) {
    if (!v.window || AXIsInOurPanel(v) || v == axButton) return NO;
    CGRect r=[v.superview convertRect:v.frame toView:nil]; CGSize screen=UIScreen.mainScreen.bounds.size;
    BOOL topRight = r.origin.x > screen.width * 0.58 && r.origin.y >= 0 && r.origin.y < screen.height * 0.16;
    BOOL searchSize = r.size.width >= 22 && r.size.width <= 340 && r.size.height >= 20 && r.size.height <= 90;
    if (!(topRight && searchSize)) return NO;
    NSString *s=AXDeepInfo(v,3);
    BOOL textHit=[s containsString:@"search"] || [s containsString:@"magnifier"] || [s containsString:@"finder"] || [s containsString:@"搜索"] || [s containsString:@"放大镜"] || [s containsString:@"搜"] || [s containsString:@"query"];
    BOOL fieldHit=[v isKindOfClass:NSClassFromString(@"UISearchBar")] || [v isKindOfClass:UITextField.class];
    BOOL classHit=[v isKindOfClass:UIButton.class] || [v isKindOfClass:UIControl.class] || [v isKindOfClass:UIImageView.class] || [v isKindOfClass:UITextField.class];
    BOOL rightSearchBox = r.origin.x > screen.width * 0.70 && r.origin.y < screen.height * 0.12 && r.size.width >= 110 && r.size.width <= 340 && r.size.height >= 26 && r.size.height <= 70;
    BOOL cornerIcon = r.origin.x > screen.width * 0.82 && r.origin.y < screen.height * 0.13 && r.size.width <= 80 && r.size.height <= 80 && classHit;
    return textHit || fieldHit || rightSearchBox || cornerIcon;
}


static void AXCollectVisibleLeafItems(UIView *root, NSMutableArray<UIView *> *items, NSInteger depth) {
    if (!root || depth > 6) return;
    if (root.hidden || root.alpha <= 0.01) return;

    CGRect r = root.superview ? [root.superview convertRect:root.frame toView:nil] : root.frame;
    CGSize screen = UIScreen.mainScreen.bounds.size;

    BOOL rightColumn = CGRectGetMidX(r) > screen.width * 0.66;
    BOOL playbackZone = CGRectGetMidY(r) > screen.height * 0.22 && CGRectGetMidY(r) < screen.height * 0.94;
    BOOL itemSize = r.size.width >= 14 && r.size.width <= 130 && r.size.height >= 14 && r.size.height <= 150;

    if (rightColumn && playbackZone && itemSize) {
        NSString *info = AXInfo(root);
        BOOL classHit = [root isKindOfClass:UIImageView.class] || [root isKindOfClass:UIButton.class] || [root isKindOfClass:UIControl.class] || [root isKindOfClass:UILabel.class];
        BOOL nameHit = [info containsString:@"digg"] || [info containsString:@"like"] || [info containsString:@"comment"] || [info containsString:@"collect"] || [info containsString:@"favorite"] || [info containsString:@"share"] || [info containsString:@"avatar"] || [info containsString:@"follow"] || [info containsString:@"action"];
        if (classHit || nameHit) [items addObject:root];
    }

    for (UIView *sub in root.subviews) AXCollectVisibleLeafItems(sub, items, depth + 1);
}

static BOOL AXLooksLikeRightButtonContainer(UIView *v) {
    if (!v.window || AXIsInOurPanel(v)) return NO;
    if (v.hidden || v.alpha <= 0.01 || !v.superview) return NO;

    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;

    // V9：容器必须位于播放页右侧中下区域，先从根上避免顶部误伤。
    if (CGRectGetMinY(r) < screen.height * 0.16) return NO;
    if (CGRectGetMidX(r) < screen.width * 0.62) return NO;
    if (r.size.width < 36 || r.size.width > screen.width * 0.42) return NO;
    if (r.size.height < screen.height * 0.20 || r.size.height > screen.height * 0.82) return NO;

    NSMutableArray<UIView *> *items = [NSMutableArray array];
    AXCollectVisibleLeafItems(v, items, 0);

    // 去掉自身被计入的情况，只看子层级中是否形成“按钮列”。
    NSMutableArray<NSValue *> *centers = [NSMutableArray array];
    for (UIView *item in items) {
        if (item == v) continue;
        if (!item.superview) continue;
        CGRect ir = [item.superview convertRect:item.frame toView:nil];
        if (CGRectGetMidX(ir) < screen.width * 0.66) continue;
        if (CGRectGetMidY(ir) < screen.height * 0.22 || CGRectGetMidY(ir) > screen.height * 0.94) continue;
        [centers addObject:[NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(ir), CGRectGetMidY(ir))]];
    }

    if (centers.count < 3) return NO;

    CGFloat minY = CGFLOAT_MAX, maxY = 0, avgX = 0;
    for (NSValue *val in centers) {
        CGPoint p = val.CGPointValue;
        minY = MIN(minY, p.y);
        maxY = MAX(maxY, p.y);
        avgX += p.x;
    }
    avgX /= MAX((CGFloat)centers.count, 1.0);

    BOOL verticalColumn = (maxY - minY) > screen.height * 0.16;
    BOOL nearRight = avgX > screen.width * 0.70;

    return verticalColumn && nearRight;
}

static CGFloat AXRightContainerScore(UIView *v) {
    if (!v || !v.superview) return -1;
    CGRect r = [v.superview convertRect:v.frame toView:nil];
    CGSize screen = UIScreen.mainScreen.bounds.size;

    CGFloat score = 0;
    score += (CGRectGetMidX(r) / screen.width) * 160.0;       // 越靠右越像
    score += (r.size.height / screen.height) * 220.0;         // 整列高度加分
    score -= (r.size.width / screen.width) * 80.0;            // 太宽扣分
    if (CGRectGetMinY(r) > screen.height * 0.22) score += 60;
    if (CGRectGetMaxY(r) < screen.height * 0.96) score += 20;

    return score;
}

static UIView *AXFindRightButtonContainerInView(UIView *root) {
    if (!root) return nil;

    UIView *best = nil;
    CGFloat bestScore = -1;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    NSInteger count = 0;

    while (stack.count && count < 1800) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        count++;

        if (v == axButton || AXIsInOurPanel(v)) continue;

        if (AXLooksLikeRightButtonContainer(v)) {
            CGFloat score = AXRightContainerScore(v);
            if (score > bestScore) {
                bestScore = score;
                best = v;
            }
        }

        for (UIView *sub in v.subviews) [stack addObject:sub];
    }

    return best;
}

static void AXApplyRightContainerScale(UIWindow *win, CGFloat scale) {
    if (!win) return;
    if (scale < 0.50) scale = 0.50;
    if (scale > 1.50) scale = 1.50;

    UIView *container = AXFindRightButtonContainerInView(win);
    if (!container) {
        if (axRightScaledContainer) axRightScaledContainer.transform = CGAffineTransformIdentity;
        axRightScaledContainer = nil;
        return;
    }

    if (axRightScaledContainer && axRightScaledContainer != container) {
        axRightScaledContainer.transform = CGAffineTransformIdentity;
    }
    axRightScaledContainer = container;

    // anchorPoint 只调整一次；反复改 anchorPoint 容易造成每秒轻微漂移。
    if (!objc_getAssociatedObject(container, &kAXRightContainerAnchorAdjustedKey)) {
        CGPoint oldOrigin = [container.superview convertPoint:container.frame.origin toView:nil];
        container.layer.anchorPoint = CGPointMake(1.0, 0.5);
        CGPoint newOrigin = [container.superview convertPoint:container.frame.origin toView:nil];
        CGFloat dx = oldOrigin.x - newOrigin.x;
        CGFloat dy = oldOrigin.y - newOrigin.y;
        container.center = CGPointMake(container.center.x + dx, container.center.y + dy);
        objc_setAssociatedObject(container, &kAXRightContainerAnchorAdjustedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    container.transform = fabs(scale - 1.0) < 0.01 ? CGAffineTransformIdentity : CGAffineTransformMakeScale(scale, scale);
}

static CGAffineTransform AXRightBottomScaleTransform(UIView *v, CGFloat scale) {
    CGFloat dx=(1.0-scale)*v.bounds.size.width*0.50;
    CGFloat dy=(1.0-scale)*v.bounds.size.height*0.50;
    CGAffineTransform t=CGAffineTransformMakeTranslation(dx, dy);
    return CGAffineTransformScale(t, scale, scale);
}

static void AXApplyVisibleSettings(void) {
    UIWindow *win=AXKeyWindow(); if(!win) return;
    CGFloat topOpacity=AXFloat(@"ax_top_opacity",1.0);
    CGFloat rightOpacity=AXFloat(@"ax_right_opacity",1.0);
    CGFloat rightScale=AXFloat(@"ax_right_buttons_scale",1.0);
    CGFloat axOpacity=AXFloat(@"ax_button_opacity",0.55);
    BOOL hideSearch=AXBool(@"ax_hide_top_search",NO);
    if(rightScale<0.50)rightScale=0.50; if(rightScale>1.50)rightScale=1.50;
    if(axOpacity<0.05)axOpacity=0.05; if(axOpacity>1.0)axOpacity=1.0;
    if(axButton) axButton.alpha=axOpacity;

    NSMutableArray<UIView*> *stack=[NSMutableArray arrayWithObject:win]; NSInteger count=0;
    while(stack.count && count<1200){
        UIView *v=stack.lastObject; [stack removeLastObject]; count++;
        if(v==axButton || AXIsInOurPanel(v)) continue;
        if(AXLooksLikeTopRightSearch(v)){
            v.hidden=hideSearch; v.alpha=hideSearch?0.0:1.0; v.userInteractionEnabled=!hideSearch;
        } else if(AXLooksLikeTopTab(v)){
            v.alpha=topOpacity;
        } else if(AXLooksLikeRightButtonItem(v)){
            v.alpha=rightOpacity;
        } else if(AXLooksLikeRightButtonLabel(v)){
            v.alpha=rightOpacity;
        }
        for(UIView *sub in v.subviews) [stack addObject:sub];
    }

    // V9：缩放只作用于右侧整列容器，避免逐个按钮 transform 导致间距错乱。
    AXApplyRightContainerScale(win, rightScale);
}

@interface AXSettingsViewController : UIViewController @end
@implementation AXSettingsViewController {
    UISlider *_topSlider; UISlider *_rightSlider; UISlider *_scaleSlider; UISlider *_axAlphaSlider;
    UISwitch *_floatSwitch; UISwitch *_hideSearchSwitch;
    UILabel *_topValue; UILabel *_rightValue; UILabel *_scaleValue; UILabel *_axAlphaValue;
}
- (void)viewDidLoad { [super viewDidLoad];
    self.view.accessibilityIdentifier=@"AXSettingsRoot"; axPanelRoot=self.view;
    self.view.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.25];
    UIVisualEffectView *card=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    card.accessibilityIdentifier=@"AXSettingsCard"; card.frame=CGRectMake(0,0,430,590); card.center=self.view.center; card.layer.cornerRadius=22; card.layer.masksToBounds=YES; [self.view addSubview:card];
    UILabel *title=[[UILabel alloc] initWithFrame:CGRectMake(0,18,430,36)]; title.text=@"AwemeX 设置 V9"; title.textColor=UIColor.whiteColor; title.textAlignment=NSTextAlignmentCenter; title.font=[UIFont boldSystemFontOfSize:18]; [card.contentView addSubview:title];
    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem]; close.frame=CGRectMake(376,18,36,36); close.layer.cornerRadius=18; close.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.25]; [close setTitle:@"×" forState:UIControlStateNormal]; close.titleLabel.font=[UIFont systemFontOfSize:30]; close.tintColor=UIColor.whiteColor; [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside]; [card.contentView addSubview:close];
    [self addLabel:@"顶部不透明度" y:72 card:card]; _topValue=[self addValueLabelY:72 card:card]; _topSlider=[self addSliderY:102 key:@"ax_top_opacity" def:1.0 min:0.0 max:1.0 card:card];
    [self addLabel:@"右侧按钮不透明度" y:148 card:card]; _rightValue=[self addValueLabelY:148 card:card]; _rightSlider=[self addSliderY:178 key:@"ax_right_opacity" def:1.0 min:0.0 max:1.0 card:card];
    [self addLabel:@"右侧按钮缩放比例度" y:224 card:card]; _scaleValue=[self addValueLabelY:224 card:card]; _scaleSlider=[self addSliderY:254 key:@"ax_right_buttons_scale" def:1.0 min:0.5 max:1.5 card:card];
    [self addLabel:@"AX 图标不透明度" y:300 card:card]; _axAlphaValue=[self addValueLabelY:300 card:card]; _axAlphaSlider=[self addSliderY:330 key:@"ax_button_opacity" def:0.55 min:0.05 max:1.0 card:card];
    UILabel *searchLabel=[[UILabel alloc] initWithFrame:CGRectMake(24,378,250,36)]; searchLabel.text=@"隐藏右上搜索"; searchLabel.textColor=UIColor.whiteColor; searchLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; [card.contentView addSubview:searchLabel];
    _hideSearchSwitch=[[UISwitch alloc] initWithFrame:CGRectMake(345,379,60,36)]; _hideSearchSwitch.on=AXBool(@"ax_hide_top_search",NO); [_hideSearchSwitch addTarget:self action:@selector(hideSearchChanged:) forControlEvents:UIControlEventValueChanged]; [card.contentView addSubview:_hideSearchSwitch];
    UILabel *floatLabel=[[UILabel alloc] initWithFrame:CGRectMake(24,426,220,36)]; floatLabel.text=@"显示 AX 悬浮按钮"; floatLabel.textColor=UIColor.whiteColor; floatLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; [card.contentView addSubview:floatLabel];
    _floatSwitch=[[UISwitch alloc] initWithFrame:CGRectMake(345,427,60,36)]; _floatSwitch.on=AXBool(@"ax_float_enabled",YES); [_floatSwitch addTarget:self action:@selector(floatChanged:) forControlEvents:UIControlEventValueChanged]; [card.contentView addSubview:_floatSwitch];
    UILabel *tip=[[UILabel alloc] initWithFrame:CGRectMake(24,474,382,36)]; tip.text=@"V9：右侧按钮改为容器级缩放，透明度仍逐个识别，减少间距错乱。"; tip.textColor=[UIColor colorWithWhite:1 alpha:0.72]; tip.font=[UIFont systemFontOfSize:12]; tip.numberOfLines=2; [card.contentView addSubview:tip];
    UIButton *reset=[UIButton buttonWithType:UIButtonTypeSystem]; reset.frame=CGRectMake(40,525,350,42); reset.backgroundColor=[[UIColor whiteColor] colorWithAlphaComponent:0.18]; reset.layer.cornerRadius=12; [reset setTitle:@"恢复默认" forState:UIControlStateNormal]; reset.tintColor=UIColor.whiteColor; [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside]; [card.contentView addSubview:reset];
    [self updateValueLabels]; }
- (void)addLabel:(NSString*)text y:(CGFloat)y card:(UIVisualEffectView*)card { UILabel*l=[[UILabel alloc]initWithFrame:CGRectMake(24,y,250,24)]; l.text=text; l.textColor=UIColor.whiteColor; l.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; [card.contentView addSubview:l]; }
- (UILabel*)addValueLabelY:(CGFloat)y card:(UIVisualEffectView*)card { UILabel*l=[[UILabel alloc]initWithFrame:CGRectMake(305,y,100,24)]; l.textColor=[UIColor colorWithWhite:1 alpha:0.85]; l.textAlignment=NSTextAlignmentRight; l.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium]; [card.contentView addSubview:l]; return l; }
- (UISlider*)addSliderY:(CGFloat)y key:(NSString*)key def:(CGFloat)def min:(CGFloat)min max:(CGFloat)max card:(UIVisualEffectView*)card { UISlider*s=[[UISlider alloc]initWithFrame:CGRectMake(24,y,382,32)]; s.value=AXFloat(key,def); s.minimumValue=min; s.maximumValue=max; s.accessibilityIdentifier=key; [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged]; [card.contentView addSubview:s]; return s; }
- (void)updateValueLabels { _topValue.text=[NSString stringWithFormat:@"%.0f%%",_topSlider.value*100.0]; _rightValue.text=[NSString stringWithFormat:@"%.0f%%",_rightSlider.value*100.0]; _scaleValue.text=[NSString stringWithFormat:@"%.2fx",_scaleSlider.value]; _axAlphaValue.text=[NSString stringWithFormat:@"%.0f%%",_axAlphaSlider.value*100.0]; }
- (void)sliderChanged:(UISlider*)sender { [[NSUserDefaults standardUserDefaults] setFloat:sender.value forKey:sender.accessibilityIdentifier]; [[NSUserDefaults standardUserDefaults] synchronize]; [self updateValueLabels]; AXApplyVisibleSettings(); }
- (void)hideSearchChanged:(UISwitch*)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ax_hide_top_search"]; [[NSUserDefaults standardUserDefaults] synchronize]; AXApplyVisibleSettings(); }
- (void)floatChanged:(UISwitch*)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.on forKey:@"ax_float_enabled"]; [[NSUserDefaults standardUserDefaults] synchronize]; if(axButton) axButton.hidden=!sender.on; }
- (void)resetTapped { [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_top_opacity"]; [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_right_opacity"]; [[NSUserDefaults standardUserDefaults] setFloat:1.0 forKey:@"ax_right_buttons_scale"]; [[NSUserDefaults standardUserDefaults] setFloat:0.55 forKey:@"ax_button_opacity"]; [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"ax_hide_top_search"]; [[NSUserDefaults standardUserDefaults] synchronize]; _topSlider.value=1.0; _rightSlider.value=1.0; _scaleSlider.value=1.0; _axAlphaSlider.value=0.55; _hideSearchSwitch.on=NO; [self updateValueLabels]; AXApplyVisibleSettings(); }
- (void)closePanel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)dealloc { if (axPanelRoot == self.view) axPanelRoot = nil; }
@end

static void AXOpenSettings(void){ UIViewController *vc=AXTopVC(); if(!vc)return; AXSettingsViewController *panel=[AXSettingsViewController new]; panel.modalPresentationStyle=UIModalPresentationOverFullScreen; panel.modalTransitionStyle=UIModalTransitionStyleCrossDissolve; [vc presentViewController:panel animated:YES completion:nil]; }
static void AXAddButton(void){ dispatch_async(dispatch_get_main_queue(), ^{ UIWindow *win=AXKeyWindow(); if(!win||axButton)return; CGFloat size=54.0; axButton=[UIButton buttonWithType:UIButtonTypeCustom]; axButton.frame=CGRectMake(210,200,size,size); axButton.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:0.6]; axButton.layer.cornerRadius=size/2.0; axButton.layer.masksToBounds=YES; axButton.alpha=AXFloat(@"ax_button_opacity",0.55); [axButton setTitle:@"AX" forState:UIControlStateNormal]; axButton.titleLabel.font=[UIFont boldSystemFontOfSize:14]; [axButton addTarget:[UIApplication sharedApplication] action:@selector(ax_openPanel) forControlEvents:UIControlEventTouchUpInside]; axButton.hidden=!AXBool(@"ax_float_enabled",YES); [win addSubview:axButton]; [win bringSubviewToFront:axButton]; if(!axTimer){ axTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(__unused NSTimer*t){ AXApplyVisibleSettings(); if(axButton&&axButton.superview)[axButton.superview bringSubviewToFront:axButton]; }]; } }); }

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)application { %orig; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXAddButton(); AXApplyVisibleSettings(); }); }
%new
- (void)ax_openPanel { AXOpenSettings(); }
%end

%ctor { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXAddButton(); AXApplyVisibleSettings(); }); }
