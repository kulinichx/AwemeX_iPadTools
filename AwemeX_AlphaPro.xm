// AwemeX V25 Overlay Opacity Controls Module
// 作用：给“昵称/文案区域”和“相关搜索条”单独增加透明度控制。
// 用法：作为独立 .xm 加进现有 AwemeX 工程编译，不要直接替换 fixed18/V23 主文件。
// 默认值：昵称文案 100%，相关搜索 55%。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const kAXOFNicknameDescAlpha = @"ax_nickname_desc_alpha";
static NSString * const kAXOFRelatedSearchAlpha = @"ax_related_search_alpha";
static char kAXOFBaseAlphaKey;
static char kAXOFSettingsAddedKey;
static UIView *axofPanel = nil;

static CGFloat AXOF_Clamp(CGFloat v) { return MIN(MAX(v, 0.0), 1.0); }

static CGFloat AXOF_Float(NSString *key, CGFloat def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v floatValue] : def;
}

static void AXOF_Set(NSString *key, id value) {
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

static UIWindow *AXOF_KeyWindow(void) {
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
    for (UIWindow *w in app.windows) if (w.isKeyWindow) return w;
    return app.windows.firstObject;
}

static CGRect AXOF_WindowFrame(UIView *v) {
    if (!v || !v.superview) return CGRectZero;
    UIWindow *w = v.window ?: AXOF_KeyWindow();
    return [v.superview convertRect:v.frame toView:w];
}

static NSString *AXOF_ViewText(UIView *v) {
    if ([v isKindOfClass:UILabel.class]) return ((UILabel *)v).text ?: @"";
    if ([v isKindOfClass:UIButton.class]) return [((UIButton *)v) titleForState:UIControlStateNormal] ?: @"";
    if ([v respondsToSelector:@selector(text)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id t = [v performSelector:@selector(text)];
#pragma clang diagnostic pop
        if ([t isKindOfClass:NSString.class]) return t;
    }
    return @"";
}

static BOOL AXOF_IsAwemeXOwnView(UIView *v) {
    UIResponder *r = v;
    while (r) {
        NSString *name = NSStringFromClass(r.class);
        if ([name containsString:@"AXMenuTarget"] || [name containsString:@"AXOFSettingsTarget"]) return YES;
        if ([r isKindOfClass:UILabel.class]) {
            NSString *t = ((UILabel *)r).text ?: @"";
            if ([t containsString:@"AwemeX 设置"] || [t containsString:@"透明度增强"]) return YES;
        }
        if ([r isKindOfClass:UIView.class]) r = ((UIView *)r).superview;
        else r = r.nextResponder;
    }
    return NO;
}

static BOOL AXOF_IsRelatedSearchView(UIView *v) {
    if (!v || !v.superview || AXOF_IsAwemeXOwnView(v)) return NO;
    NSString *cls = NSStringFromClass(v.class);
    NSString *txt = AXOF_ViewText(v);
    if ([txt containsString:@"相关搜索"] || ([txt containsString:@"搜索"] && txt.length <= 28)) return YES;
    if ([cls containsString:@"RelatedSearch"] || [cls containsString:@"RelationSearch"] ||
        [cls containsString:@"SearchEntrance"] || [cls containsString:@"SearchBar"] ||
        [cls containsString:@"SearchHint"] || [cls containsString:@"FeedSearch"]) return YES;

    // 坐标兜底：底部偏上的横向搜索条，只处理叶子文本/图标/按钮，避免误伤 Feed 容器。
    if (![v isKindOfClass:UILabel.class] && ![v isKindOfClass:UIButton.class] && ![v isKindOfClass:UIImageView.class]) return NO;
    CGRect f = AXOF_WindowFrame(v);
    CGSize s = UIScreen.mainScreen.bounds.size;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;
    BOOL looksLikeBottomSearch = f.origin.y > s.height * 0.48 && f.origin.y < s.height * 0.72 &&
                                 f.origin.x < s.width * 0.18 && f.size.width > s.width * 0.22 &&
                                 f.size.height < 80.0;
    return looksLikeBottomSearch && txt.length > 0 && [txt containsString:@"搜索"];
}

static BOOL AXOF_IsNicknameDescView(UIView *v) {
    if (!v || !v.superview || AXOF_IsAwemeXOwnView(v)) return NO;
    if (![v isKindOfClass:UILabel.class] && ![v isKindOfClass:UIButton.class] && ![v isKindOfClass:UIImageView.class]) return NO;
    if (AXOF_IsRelatedSearchView(v)) return NO;

    NSString *cls = NSStringFromClass(v.class);
    NSString *txt = AXOF_ViewText(v);
    if ([cls containsString:@"Nick"] || [cls containsString:@"Author"] || [cls containsString:@"Desc"] ||
        [cls containsString:@"Caption"] || [cls containsString:@"TitleLabel"] || [cls containsString:@"FeedAnchor"]) return YES;
    if ([txt hasPrefix:@"@"] || [txt containsString:@"#"] || [txt containsString:@"IP属地"] ||
        [txt containsString:@"作者声明"] || [txt containsString:@"虚构演绎"]) return YES;

    CGRect f = AXOF_WindowFrame(v);
    CGSize s = UIScreen.mainScreen.bounds.size;
    if (CGRectIsEmpty(f) || f.size.width <= 0 || f.size.height <= 0) return NO;

    // iPad 横屏/竖屏都尽量只处理下方昵称文案叶子控件，不处理右侧按钮栏和底部 Tab。
    BOOL leftOrCenterTextArea = f.origin.x < s.width * 0.72 &&
                                f.origin.y > s.height * 0.28 && f.origin.y < s.height * 0.76 &&
                                f.size.width < s.width * 0.82 && f.size.height < 140.0;
    return leftOrCenterTextArea && txt.length > 0;
}

static void AXOF_ApplyAlpha(UIView *v, CGFloat alpha) {
    if (!v) return;
    alpha = AXOF_Clamp(alpha);
    NSNumber *base = objc_getAssociatedObject(v, &kAXOFBaseAlphaKey);
    CGFloat baseAlpha = base ? base.floatValue : v.alpha;
    if (!base) objc_setAssociatedObject(v, &kAXOFBaseAlphaKey, @(baseAlpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat finalAlpha = AXOF_Clamp(baseAlpha * alpha);
    if (fabs(v.alpha - finalAlpha) > 0.001) v.alpha = finalAlpha;
}

static void AXOF_ApplyView(UIView *v) {
    if (!v) return;
    if (AXOF_IsRelatedSearchView(v)) {
        AXOF_ApplyAlpha(v, AXOF_Float(kAXOFRelatedSearchAlpha, 0.55));
        return;
    }
    if (AXOF_IsNicknameDescView(v)) {
        AXOF_ApplyAlpha(v, AXOF_Float(kAXOFNicknameDescAlpha, 1.00));
        return;
    }
}

static void AXOF_RefreshRecursive(UIView *v) {
    if (!v) return;
    AXOF_ApplyView(v);
    for (UIView *sub in v.subviews) AXOF_RefreshRecursive(sub);
}

static void AXOF_RefreshAll(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) AXOF_RefreshRecursive(w);
        }
        return;
    }
    for (UIWindow *w in app.windows) AXOF_RefreshRecursive(w);
}

@interface AXOFSettingsTarget : NSObject
+ (instancetype)shared;
- (void)openOpacityPanel;
- (void)closeOpacityPanel;
- (void)sliderChanged:(UISlider *)sender;
@end

@implementation AXOFSettingsTarget
+ (instancetype)shared {
    static AXOFSettingsTarget *t;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ t = [AXOFSettingsTarget new]; });
    return t;
}

- (void)closeOpacityPanel { [axofPanel removeFromSuperview]; axofPanel = nil; }

- (void)sliderChanged:(UISlider *)sender {
    NSString *key = sender.tag == 2501 ? kAXOFNicknameDescAlpha : kAXOFRelatedSearchAlpha;
    AXOF_Set(key, @(sender.value));
    UILabel *val = [axofPanel viewWithTag:sender.tag + 100];
    val.text = [NSString stringWithFormat:@"%.0f%%", sender.value * 100.0];
    AXOF_RefreshAll();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXOF_RefreshAll(); });
}

- (void)openOpacityPanel {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXOF_KeyWindow();
        if (!w) return;
        if (axofPanel) { [self closeOpacityPanel]; return; }
        CGRect b = UIScreen.mainScreen.bounds;
        CGFloat width = MIN(430.0, b.size.width - 80.0);
        CGFloat height = 230.0;
        axofPanel = [[UIView alloc] initWithFrame:CGRectMake((b.size.width - width) / 2.0, (b.size.height - height) / 2.0, width, height)];
        axofPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.86];
        axofPanel.layer.cornerRadius = 18;
        axofPanel.clipsToBounds = YES;
        axofPanel.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:axofPanel];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 18, width, 26)];
        title.text = @"透明度增强";
        title.textColor = UIColor.whiteColor;
        title.textAlignment = NSTextAlignmentCenter;
        title.font = [UIFont boldSystemFontOfSize:17];
        [axofPanel addSubview:title];

        UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
        close.frame = CGRectMake(width - 48, 14, 36, 34);
        [close setTitle:@"×" forState:UIControlStateNormal];
        [close setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        close.titleLabel.font = [UIFont boldSystemFontOfSize:24];
        [close addTarget:self action:@selector(closeOpacityPanel) forControlEvents:UIControlEventTouchUpInside];
        [axofPanel addSubview:close];

        NSArray *names = @[@"昵称/文案不透明度", @"相关搜索不透明度"];
        NSArray *keys = @[kAXOFNicknameDescAlpha, kAXOFRelatedSearchAlpha];
        NSArray *defs = @[@1.00, @0.55];
        for (NSInteger i = 0; i < 2; i++) {
            CGFloat y = 62 + i * 72;
            UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(28, y, width - 150, 24)];
            l.text = names[i];
            l.textColor = UIColor.whiteColor;
            l.font = [UIFont boldSystemFontOfSize:15];
            [axofPanel addSubview:l];

            UILabel *val = [[UILabel alloc] initWithFrame:CGRectMake(width - 100, y, 70, 24)];
            val.textAlignment = NSTextAlignmentRight;
            val.textColor = UIColor.whiteColor;
            val.font = [UIFont systemFontOfSize:14];
            CGFloat cur = AXOF_Float(keys[i], [defs[i] floatValue]);
            val.text = [NSString stringWithFormat:@"%.0f%%", cur * 100.0];
            val.tag = 2601 + i;
            [axofPanel addSubview:val];

            UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(28, y + 30, width - 56, 32)];
            s.tag = 2501 + i;
            s.minimumValue = 0.05;
            s.maximumValue = 1.0;
            s.value = cur;
            [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
            [axofPanel addSubview:s];
        }
    });
}
@end

static UIView *AXOF_FindAwemeXSettingsPanel(void) {
    UIWindow *w = AXOF_KeyWindow();
    if (!w) return nil;
    for (UIView *v in [w.subviews reverseObjectEnumerator]) {
        for (UIView *sub in v.subviews) {
            if ([sub isKindOfClass:UILabel.class]) {
                NSString *t = ((UILabel *)sub).text ?: @"";
                if ([t containsString:@"AwemeX 设置"]) return v;
            }
        }
    }
    return nil;
}

static void AXOF_AddSettingsEntryButton(void) {
    UIView *panel = AXOF_FindAwemeXSettingsPanel();
    if (!panel) return;
    NSNumber *added = objc_getAssociatedObject(panel, &kAXOFSettingsAddedKey);
    if (added.boolValue) return;

    CGFloat width = panel.bounds.size.width;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(30, MAX(52, panel.bounds.size.height - 98), width - 60, 34);
    btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.16];
    btn.layer.cornerRadius = 9;
    [btn setTitle:@"文案/相关搜索透明度" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [btn addTarget:[AXOFSettingsTarget shared] action:@selector(openOpacityPanel) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:btn];
    objc_setAssociatedObject(panel, &kAXOFSettingsAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook AXMenuTarget
- (void)openSettings {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ AXOF_AddSettingsEntryButton(); });
}
%end

%hook UILabel
- (void)layoutSubviews { %orig; AXOF_ApplyView((UIView *)self); }
- (void)didMoveToWindow { %orig; AXOF_ApplyView((UIView *)self); }
%end

%hook UIButton
- (void)layoutSubviews { %orig; AXOF_ApplyView((UIView *)self); }
- (void)didMoveToWindow { %orig; AXOF_ApplyView((UIView *)self); }
%end

%hook UIImageView
- (void)layoutSubviews { %orig; AXOF_ApplyView((UIView *)self); }
- (void)didMoveToWindow { %orig; AXOF_ApplyView((UIView *)self); }
%end

%hook UIView
- (void)layoutSubviews {
    %orig;
    NSString *cls = NSStringFromClass(self.class);
    if ([cls containsString:@"RelatedSearch"] || [cls containsString:@"SearchEntrance"] || [cls containsString:@"FeedSearch"]) {
        AXOF_ApplyAlpha((UIView *)self, AXOF_Float(kAXOFRelatedSearchAlpha, 0.55));
    }
}
%end

%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXOF_RefreshAll(); });
}
%end

%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ AXOF_RefreshAll(); });
}
