// AwemeX iPad 单指长按菜单：只追加保存按钮，不改菜单背景/布局
// 用法：把本模块粘贴到现有 AwemeX_AlphaPro.xm 末尾，重新 make package。
// 目标：在 AWEUserActionSheetView 的 actions 里追加：保存视频 / 保存封面 / 保存音频 / 保存图片。
// 注意：这是安全测试模块，默认开启；如果按钮出现但保存失败，说明当前抖音版本的 awemeModel 字段名需要再适配。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const kAXAppendSaveButtons = @"ax_append_save_buttons";
static char kAXSaveButtonsInjectedKey;

static BOOL AXSB_Bool(NSString *key, BOOL def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v boolValue] : def;
}

static id AXSB_Send0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static BOOL AXSB_StrHasHTTP(NSString *s) {
    return [s isKindOfClass:NSString.class] && ([s hasPrefix:@"http://"] || [s hasPrefix:@"https://"]);
}

static NSURL *AXSB_URLFromString(NSString *s) {
    if (!AXSB_StrHasHTTP(s)) return nil;
    return [NSURL URLWithString:s];
}

static NSURL *AXSB_FirstURLInObject(id obj, NSInteger depth);

static NSURL *AXSB_FirstURLBySelectors(id obj, NSArray<NSString *> *sels, NSInteger depth) {
    if (!obj || depth <= 0) return nil;
    for (NSString *name in sels) {
        SEL sel = NSSelectorFromString(name);
        id value = AXSB_Send0(obj, sel);
        NSURL *u = AXSB_FirstURLInObject(value, depth - 1);
        if (u) return u;
    }
    return nil;
}

static NSURL *AXSB_FirstURLInObject(id obj, NSInteger depth) {
    if (!obj || depth <= 0) return nil;

    if ([obj isKindOfClass:NSURL.class]) return (NSURL *)obj;
    if ([obj isKindOfClass:NSString.class]) return AXSB_URLFromString((NSString *)obj);

    if ([obj isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)obj) {
            NSURL *u = AXSB_FirstURLInObject(item, depth - 1);
            if (u) return u;
        }
        return nil;
    }

    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = (NSDictionary *)obj;
        NSArray *preferred = @[@"urlList", @"url_list", @"urls", @"url", @"URL", @"uri", @"playAddr", @"downloadAddr", @"cover", @"originCover", @"playUrl"];
        for (NSString *k in preferred) {
            NSURL *u = AXSB_FirstURLInObject(dict[k], depth - 1);
            if (u) return u;
        }
        for (id value in dict.allValues) {
            NSURL *u = AXSB_FirstURLInObject(value, depth - 1);
            if (u) return u;
        }
        return nil;
    }

    NSArray *common = @[
        @"urlList", @"URLList", @"url_list", @"urls", @"url", @"URL", @"uri",
        @"playAddr", @"downloadAddr", @"playURL", @"playUrl", @"originURL", @"originUrl",
        @"cover", @"originCover", @"dynamicCover", @"animatedCover", @"coverUrl", @"coverURL",
        @"image", @"imageURL", @"imageUrl", @"imageUrlModel", @"urlModel"
    ];
    return AXSB_FirstURLBySelectors(obj, common, depth - 1);
}

static UIViewController *AXSB_TopVCFrom(UIViewController *vc) {
    if (!vc) return nil;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    if ([vc isKindOfClass:UINavigationController.class]) return AXSB_TopVCFrom(((UINavigationController *)vc).topViewController);
    if ([vc isKindOfClass:UITabBarController.class]) return AXSB_TopVCFrom(((UITabBarController *)vc).selectedViewController);
    return vc;
}

static UIWindow *AXSB_KeyWindow(void) {
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

static UIViewController *AXSB_FindPlayVCInTree(UIViewController *vc) {
    if (!vc) return nil;
    NSString *name = NSStringFromClass(vc.class);
    if ([name containsString:@"AWEPlayInteractionViewController"] || [name containsString:@"PlayInteraction"]) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        UIViewController *hit = AXSB_FindPlayVCInTree(child);
        if (hit) return hit;
    }
    return nil;
}

static UIViewController *AXSB_CurrentPlayVC(void) {
    UIWindow *w = AXSB_KeyWindow();
    UIViewController *top = AXSB_TopVCFrom(w.rootViewController);
    UIViewController *hit = AXSB_FindPlayVCInTree(top);
    if (hit) return hit;
    return AXSB_FindPlayVCInTree(w.rootViewController);
}

static id AXSB_CurrentAwemeModel(void) {
    UIViewController *vc = AXSB_CurrentPlayVC();
    NSArray *sels = @[@"awemeModel", @"aweme", @"model", @"currentAweme", @"currentAwemeModel", @"currentModel", @"item"];
    for (NSString *name in sels) {
        id value = AXSB_Send0(vc, NSSelectorFromString(name));
        if (value) return value;
    }
    return nil;
}

static NSURL *AXSB_VideoURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id video = AXSB_Send0(aweme, @selector(video));
    NSURL *u = AXSB_FirstURLBySelectors(video ?: aweme, @[@"downloadAddr", @"playAddr", @"h264PlayAddr", @"playApi", @"bitRate", @"video"], 6);
    return u ?: AXSB_FirstURLInObject(video ?: aweme, 5);
}

static NSURL *AXSB_CoverURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id video = AXSB_Send0(aweme, @selector(video));
    NSURL *u = AXSB_FirstURLBySelectors(video ?: aweme, @[@"originCover", @"cover", @"dynamicCover", @"animatedCover", @"coverUrl", @"coverURL"], 5);
    return u;
}

static NSURL *AXSB_AudioURLFromAweme(id aweme) {
    if (!aweme) return nil;
    id music = AXSB_Send0(aweme, @selector(music));
    if (!music) music = AXSB_Send0(aweme, @selector(musicModel));
    NSURL *u = AXSB_FirstURLBySelectors(music ?: aweme, @[@"playUrl", @"playURL", @"playUrlModel", @"downloadUrl", @"downloadURL", @"urlModel"], 6);
    return u;
}

static NSArray<NSURL *> *AXSB_ImageURLsFromAweme(id aweme) {
    if (!aweme) return @[];
    NSMutableArray<NSURL *> *out = [NSMutableArray array];
    NSArray *containers = @[
        AXSB_Send0(aweme, @selector(images)),
        AXSB_Send0(aweme, @selector(imageInfos)),
        AXSB_Send0(aweme, @selector(albumImages)),
        AXSB_Send0(aweme, @selector(imageAlbum)),
        AXSB_Send0(aweme, @selector(imagePostInfo))
    ];
    for (id c in containers) {
        if (!c) continue;
        if ([c isKindOfClass:NSArray.class]) {
            for (id item in (NSArray *)c) {
                NSURL *u = AXSB_FirstURLInObject(item, 6);
                if (u && ![out containsObject:u]) [out addObject:u];
            }
        } else {
            NSURL *u = AXSB_FirstURLInObject(c, 6);
            if (u && ![out containsObject:u]) [out addObject:u];
        }
    }
    return out;
}

static void AXSB_Toast(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *w = AXSB_KeyWindow();
        if (!w) return;
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 260, 44)];
        l.center = CGPointMake(CGRectGetMidX(w.bounds), CGRectGetMidY(w.bounds));
        l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.78];
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont boldSystemFontOfSize:14];
        l.textAlignment = NSTextAlignmentCenter;
        l.text = text;
        l.layer.cornerRadius = 12;
        l.clipsToBounds = YES;
        l.layer.zPosition = CGFLOAT_MAX;
        [w addSubview:l];
        [UIView animateWithDuration:0.25 delay:1.15 options:0 animations:^{ l.alpha = 0; } completion:^(BOOL finished) { [l removeFromSuperview]; }];
    });
}

static void AXSB_SaveImageURL(NSURL *url, NSString *name) {
    if (!url) { AXSB_Toast([NSString stringWithFormat:@"%@链接为空", name]); return; }
    AXSB_Toast([NSString stringWithFormat:@"正在保存%@…", name]);
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *img = data ? [UIImage imageWithData:data] : nil;
        if (!img) { AXSB_Toast([NSString stringWithFormat:@"%@保存失败", name]); return; }
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil);
        AXSB_Toast([NSString stringWithFormat:@"%@已保存到相册", name]);
    }] resume];
}

static void AXSB_SaveVideoURL(NSURL *url) {
    if (!url) { AXSB_Toast(@"视频链接为空"); return; }
    AXSB_Toast(@"正在保存视频…");
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!location || error) { AXSB_Toast(@"视频下载失败"); return; }
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"awemex_%@.mp4", NSUUID.UUID.UUIDString]];
        NSURL *dst = [NSURL fileURLWithPath:tmp];
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        NSError *moveErr = nil;
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dst error:&moveErr];
        if (moveErr) { AXSB_Toast(@"视频缓存失败"); return; }
        UISaveVideoAtPathToSavedPhotosAlbum(tmp, nil, nil, nil);
        AXSB_Toast(@"视频已保存到相册");
    }];
    [task resume];
}

static void AXSB_ShareAudioURL(NSURL *url) {
    if (!url) { AXSB_Toast(@"音频链接为空"); return; }
    AXSB_Toast(@"正在准备音频…");
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (!location || error) { AXSB_Toast(@"音频下载失败"); return; }
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"awemex_audio_%@.m4a", NSUUID.UUID.UUIDString]];
        NSURL *dst = [NSURL fileURLWithPath:tmp];
        [[NSFileManager defaultManager] removeItemAtURL:dst error:nil];
        [[NSFileManager defaultManager] moveItemAtURL:location toURL:dst error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *vc = AXSB_TopVCFrom(AXSB_KeyWindow().rootViewController);
            UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[dst] applicationActivities:nil];
            avc.popoverPresentationController.sourceView = vc.view;
            avc.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
            [vc presentViewController:avc animated:YES completion:nil];
        });
    }];
    [task resume];
}

static void AXSB_HandleSaveKind(NSString *kind) {
    id aweme = AXSB_CurrentAwemeModel();
    if (!aweme) { AXSB_Toast(@"未找到当前视频模型"); return; }
    if ([kind isEqualToString:@"video"]) {
        AXSB_SaveVideoURL(AXSB_VideoURLFromAweme(aweme));
    } else if ([kind isEqualToString:@"cover"]) {
        AXSB_SaveImageURL(AXSB_CoverURLFromAweme(aweme), @"封面");
    } else if ([kind isEqualToString:@"audio"]) {
        AXSB_ShareAudioURL(AXSB_AudioURLFromAweme(aweme));
    } else if ([kind isEqualToString:@"image"]) {
        NSArray<NSURL *> *urls = AXSB_ImageURLsFromAweme(aweme);
        if (urls.count == 0) { AXSB_Toast(@"图片链接为空"); return; }
        AXSB_Toast([NSString stringWithFormat:@"正在保存%lu张图片…", (unsigned long)urls.count]);
        for (NSURL *u in urls) AXSB_SaveImageURL(u, @"图片");
    }
}

static id AXSB_MakeAction(NSString *title, NSString *kind) {
    Class cls = NSClassFromString(@"AWEUserSheetAction");
    if (!cls) return nil;

    void (^handler)(id) = ^(id action) { AXSB_HandleSaveKind(kind); };
    UIImage *img = nil;
    if (@available(iOS 13.0, *)) {
        NSString *sys = [kind isEqualToString:@"video"] ? @"arrow.down.circle" :
                        [kind isEqualToString:@"cover"] ? @"photo" :
                        [kind isEqualToString:@"audio"] ? @"music.note" : @"photo.on.rectangle";
        img = [UIImage systemImageNamed:sys];
    }

    SEL s1 = NSSelectorFromString(@"actionWithTitle:description:image:imageStyle:handler:");
    if ([cls respondsToSelector:s1]) {
        return ((id (*)(id, SEL, id, id, id, NSInteger, id))objc_msgSend)(cls, s1, title, nil, img, 0, handler);
    }

    SEL s2 = NSSelectorFromString(@"actionWithTitle:image:handler:");
    if ([cls respondsToSelector:s2]) {
        return ((id (*)(id, SEL, id, id, id))objc_msgSend)(cls, s2, title, img, handler);
    }

    SEL s3 = NSSelectorFromString(@"actionWithTitle:handler:");
    if ([cls respondsToSelector:s3]) {
        return ((id (*)(id, SEL, id, id))objc_msgSend)(cls, s3, title, handler);
    }
    return nil;
}

static NSString *AXSB_ActionTitle(id action) {
    id t = AXSB_Send0(action, @selector(title));
    if (!t) t = AXSB_Send0(action, @selector(actionTitle));
    if (!t) t = AXSB_Send0(action, @selector(text));
    return [t isKindOfClass:NSString.class] ? (NSString *)t : nil;
}

static NSArray *AXSB_ActionsByAppendingSaveButtons(NSArray *actions, id sheet) {
    if (!AXSB_Bool(kAXAppendSaveButtons, YES)) return actions;
    if (![actions isKindOfClass:NSArray.class]) return actions;

    NSNumber *done = objc_getAssociatedObject(sheet, &kAXSaveButtonsInjectedKey);
    if (done.boolValue) return actions;

    NSMutableArray *m = [actions mutableCopy];
    NSArray *titles = @[@"保存视频", @"保存封面", @"保存音频", @"保存图片"];
    NSArray *kinds = @[@"video", @"cover", @"audio", @"image"];

    for (NSInteger i = 0; i < titles.count; i++) {
        BOOL exists = NO;
        for (id a in m) {
            NSString *t = AXSB_ActionTitle(a);
            if ([t isEqualToString:titles[i]]) { exists = YES; break; }
        }
        if (!exists) {
            id action = AXSB_MakeAction(titles[i], kinds[i]);
            if (action) [m addObject:action];
        }
    }

    objc_setAssociatedObject(sheet, &kAXSaveButtonsInjectedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return m;
}

%hook AWEUserActionSheetView
- (void)setActions:(NSArray *)actions {
    NSArray *patched = AXSB_ActionsByAppendingSaveButtons(actions, self);
    %orig(patched);
}
%end

