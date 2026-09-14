// AwemeX_iPadCompat v0.3-probe
// Runtime-only iPad compatibility/probe layer for AwemeX 2.6.2.
// Scope: v0.2 search/sidebar/right-stack fixes + a TARGETED long-press probe
// on AWEPlayInteractionViewController. The probe does not download anything.
// It forwards a one-finger long press into the existing showDislikeOnVideo
// action so the device test can tell us whether AwemeX's own downstream
// long-press/media hook is already reachable on iPad.
//
// IMPORTANT: this is a diagnostic probe, not the final media implementation.
// No global UIView hooks, no timers, no downloader, no network code,
// no independent preferences UI.
//
// The scaling bridge does NOT implement a second scaling algorithm. It only asks
// AwemeX's own `awe_applySafeScaling` helper to re-apply its existing transform
// on the two iPad stack classes used by AlphaPro. This preserves AwemeX's own
// scaling preference/limits and avoids the AlphaPro-wide UIView layout fallback.

// Intentionally avoids private SDK headers. Theos can link this as a normal dylib.

#include <dispatch/dispatch.h>

typedef unsigned char BOOL;
typedef unsigned long NSUInteger;
typedef struct objc_object *id;
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef struct objc_method *Method;
typedef void (*IMP)(void);

#ifndef NULL
#define NULL ((void *)0)
#endif

extern Class objc_getClass(const char *name);
extern int objc_getClassList(Class *buffer, int bufferCount);
extern Class object_getClass(id obj);
extern Class class_getSuperclass(Class cls);
extern Method class_getInstanceMethod(Class cls, SEL name);
extern Method class_getClassMethod(Class cls, SEL name);
extern Method *class_copyMethodList(Class cls, unsigned int *outCount);
extern SEL method_getName(Method m);
extern IMP method_getImplementation(Method m);
extern IMP method_setImplementation(Method m, IMP imp);
extern const char *method_getTypeEncoding(Method m);
extern BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
extern SEL sel_registerName(const char *str);
extern void *objc_msgSend(void);
extern id objc_getAssociatedObject(id object, const void *key);
extern void objc_setAssociatedObject(id object, const void *key, id value, unsigned long policy);
extern void objc_release(id value);
extern void *malloc(unsigned long size);
extern void free(void *ptr);

#define MAX_HOOKS 64
#define OBJC_ASSOCIATION_RETAIN_NONATOMIC 1UL

// AwemeX 2.6.2's obfuscated MyDefaults BOOL getter.
static const char *kMyDefaultsBoolGetter = "g24MPeX47iRQ9mJBhaKvZx6F:";

// UTF-8 preference keys used by AwemeX. Hex escapes avoid source-encoding issues.
static const char kPrefHideSearch[] =
    "\xe9\x9a\x90\xe8\x97\x8f\xe6\x89\x93\xe5\xbc\x80\xe8\xaf\x84\xe8\xae\xba\xe5\x8f\xb3\xe4\xb8\x8a\xe6\x90\x9c\xe7\xb4\xa2"; // 隐藏打开评论右上搜索
static const char kPrefHideSidebar1[] =
    "\xe7\xa7\xbb\xe9\x99\xa4\xe5\xb7\xa6\xe4\xbe\xa7\xe8\xbf\x9b\xe5\x85\xa5\xe5\x85\xa5\xe5\x8f\xa3"; // 移除左侧进入入口
static const char kPrefHideSidebar2[] =
    "\xe7\xa7\xbb\xe9\x99\xa4\xe5\xb7\xa6\xe4\xbe\xa7\xe8\xbf\x9b\xe5\x85\xa5"; // 移除左侧进入

typedef struct {
    Class cls;
    SEL sel;
    IMP original;
    IMP replacement;
} HookRecord;

static HookRecord gHooks[MAX_HOOKS];
static unsigned int gHookCount = 0;
static BOOL gRetryScheduled = 0;
static BOOL gInstalledSearchA = 0;
static BOOL gInstalledSearchB = 0;
static BOOL gInstalledRightStackA = 0;
static BOOL gInstalledRightStackB = 0;
static BOOL gInstalledLongPressProbe = 0;
static unsigned char gLongPressRecognizerKey = 0;

static id makeNSString(const char *utf8) {
    Class nsString = objc_getClass("NSString");
    if (!nsString || !utf8) return NULL;
    SEL s = sel_registerName("stringWithUTF8String:");
    return ((id (*)(id, SEL, const char *))objc_msgSend)((id)nsString, s, utf8);
}

static BOOL awxBoolPref(const char *key) {
    Class defaults = objc_getClass("MyDefaults");
    if (!defaults || !key) return 0;

    SEL getter = sel_registerName(kMyDefaultsBoolGetter);
    if (!class_getClassMethod(defaults, getter)) return 0;

    id keyObj = makeNSString(key);
    if (!keyObj) return 0;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)((id)defaults, getter, keyObj);
}

static BOOL shouldHideSearch(void) {
    return awxBoolPref(kPrefHideSearch);
}

static BOOL shouldHideSidebar(void) {
    // Support both names observed in AwemeX's sidebar paths.
    return awxBoolPref(kPrefHideSidebar1) || awxBoolPref(kPrefHideSidebar2);
}

static BOOL isPad(void) {
    Class deviceClass = objc_getClass("UIDevice");
    if (!deviceClass) return 0;
    SEL currentSel = sel_registerName("currentDevice");
    SEL idiomSel = sel_registerName("userInterfaceIdiom");
    id device = ((id (*)(id, SEL))objc_msgSend)((id)deviceClass, currentSel);
    if (!device) return 0;
    long idiom = ((long (*)(id, SEL))objc_msgSend)(device, idiomSel);
    return idiom == 1; // UIUserInterfaceIdiomPad
}

static void enforceHiddenView(id view) {
    if (!view) return;

    SEL isHiddenSel = sel_registerName("isHidden");
    SEL setHiddenSel = sel_registerName("setHidden:");
    SEL alphaSel = sel_registerName("alpha");
    SEL setAlphaSel = sel_registerName("setAlpha:");
    SEL interactiveSel = sel_registerName("isUserInteractionEnabled");
    SEL setInteractiveSel = sel_registerName("setUserInteractionEnabled:");

    // Idempotent writes: do not re-set properties on every layout if already correct.
    BOOL hidden = ((BOOL (*)(id, SEL))objc_msgSend)(view, isHiddenSel);
    if (!hidden) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view, setHiddenSel, 1);
    }

    double alpha = ((double (*)(id, SEL))objc_msgSend)(view, alphaSel);
    if (alpha != 0.0) {
        ((void (*)(id, SEL, double))objc_msgSend)(view, setAlphaSel, 0.0);
    }

    BOOL interactive = ((BOOL (*)(id, SEL))objc_msgSend)(view, interactiveSel);
    if (interactive) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view, setInteractiveSel, 0);
    }
}

static IMP findOriginal(id self, SEL sel, IMP replacement) {
    Class c = object_getClass(self);
    while (c) {
        for (unsigned int i = 0; i < gHookCount; i++) {
            if (gHooks[i].cls == c && gHooks[i].sel == sel && gHooks[i].replacement == replacement) {
                return gHooks[i].original;
            }
        }
        c = class_getSuperclass(c);
    }
    return NULL;
}

static Method directMethod(Class cls, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (!methods) return NULL;
    Method found = NULL;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) {
            found = methods[i];
            break;
        }
    }
    free(methods);
    return found;
}

static BOOL recordExists(Class cls, SEL sel, IMP replacement) {
    for (unsigned int i = 0; i < gHookCount; i++) {
        if (gHooks[i].cls == cls && gHooks[i].sel == sel && gHooks[i].replacement == replacement) return 1;
    }
    return 0;
}

static BOOL hookMethod(Class cls, SEL sel, IMP replacement) {
    if (!cls || !sel || !replacement || gHookCount >= MAX_HOOKS) return 0;
    if (recordExists(cls, sel, replacement)) return 1;

    Method effective = class_getInstanceMethod(cls, sel);
    if (!effective) return 0;

    IMP original = method_getImplementation(effective);
    if (!original || original == replacement) return 0;
    const char *types = method_getTypeEncoding(effective);

    // If the method is inherited, add an override on this class instead of mutating the superclass.
    Method direct = directMethod(cls, sel);

    gHooks[gHookCount].cls = cls;
    gHooks[gHookCount].sel = sel;
    gHooks[gHookCount].original = original;
    gHooks[gHookCount].replacement = replacement;
    gHookCount++;

    if (!direct) {
        if (class_addMethod(cls, sel, replacement, types)) return 1;
        // Race/fallback: method appeared directly after our inspection.
        direct = directMethod(cls, sel);
    }

    if (direct) {
        method_setImplementation(direct, replacement);
        return 1;
    }
    return 0;
}


// -------- Targeted right-side scaling bridge --------
// Static analysis of AwemeX 2.6.2 found its own helper selector
// `awe_applySafeScaling`. That method computes/clamps its scale from AwemeX's
// own configuration and applies a transform. AlphaPro's broad UIView fallback
// was added because the iPad stack views can miss the original timing/path.
//
// We therefore do not read ax_scale and do not reproduce the scaling math.
// We only re-trigger AwemeX's own helper on two concrete iPad stack classes.

static BOOL objectResponds(id obj, const char *selectorName) {
    if (!obj || !selectorName) return 0;
    SEL respondsSel = sel_registerName("respondsToSelector:");
    SEL targetSel = sel_registerName(selectorName);
    return ((BOOL (*)(id, SEL, SEL))objc_msgSend)(obj, respondsSel, targetSel);
}

static id sendId0(id obj, const char *selectorName) {
    if (!obj || !selectorName) return NULL;
    SEL sel = sel_registerName(selectorName);
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static BOOL invokeAwemeXSafeScaling(id view) {
    if (!view) return 0;
    const char *safeSelName = "awe_applySafeScaling";
    SEL safeSel = sel_registerName(safeSelName);

    // Preferred path: AwemeX attached the helper directly to this concrete view.
    if (objectResponds(view, safeSelName)) {
        ((void (*)(id, SEL))objc_msgSend)(view, safeSel);
        return 1;
    }

    // Conservative fallback: a small superview walk only. Do not scan the whole
    // hierarchy and do not walk all live UIViews as AlphaPro's global fallback did.
    id node = view;
    for (int depth = 0; depth < 4; depth++) {
        node = sendId0(node, "superview");
        if (!node) break;
        if (objectResponds(node, safeSelName)) {
            ((void (*)(id, SEL))objc_msgSend)(node, safeSel);
            return 1;
        }
    }
    return 0;
}

static void compatRightStackLayoutHook(id self, SEL _cmd) {
    IMP original = findOriginal(self, _cmd, (IMP)compatRightStackLayoutHook);
    if (original) ((void (*)(id, SEL))original)(self, _cmd);

    // Intentionally specific to two stack classes. Calling AwemeX's existing
    // helper is idempotent from our side: we do not set frame/transform directly.
    invokeAwemeXSafeScaling(self);
}

static BOOL installRightStackClass(const char *className) {
    Class cls = objc_getClass(className);
    if (!cls) return 0;

    // layoutSubviews is kept only on these two classes because AlphaPro's iPad
    // workaround indicates the right-side transform can be reset during feed
    // relayout. There is deliberately no UIView-wide hook.
    BOOL a = hookMethod(cls, sel_registerName("layoutSubviews"), (IMP)compatRightStackLayoutHook);
    BOOL b = hookMethod(cls, sel_registerName("didMoveToWindow"), (IMP)compatRightStackLayoutHook);
    return a || b;
}

static void compatSearchVoidHook(id self, SEL _cmd) {
    IMP original = findOriginal(self, _cmd, (IMP)compatSearchVoidHook);
    if (original) ((void (*)(id, SEL))original)(self, _cmd);
    if (shouldHideSearch()) enforceHiddenView(self);
}

static id compatSidebarViewHook(id self, SEL _cmd) {
    IMP original = findOriginal(self, _cmd, (IMP)compatSidebarViewHook);
    id view = original ? ((id (*)(id, SEL))original)(self, _cmd) : NULL;
    if (view && shouldHideSidebar()) enforceHiddenView(view);
    return view;
}

static BOOL compatSidebarCanShowHook(id self, SEL _cmd, id identifier) {
    if (shouldHideSidebar()) return 0;
    IMP original = findOriginal(self, _cmd, (IMP)compatSidebarCanShowHook);
    return original ? ((BOOL (*)(id, SEL, id))original)(self, _cmd, identifier) : 0;
}

static BOOL installSearchClass(const char *className) {
    Class cls = objc_getClass(className);
    if (!cls) return 0;

    BOOL a = hookMethod(cls, sel_registerName("layoutSubviews"), (IMP)compatSearchVoidHook);
    BOOL b = hookMethod(cls, sel_registerName("didMoveToWindow"), (IMP)compatSearchVoidHook);
    return a || b;
}

static void installSidebarHooks(void) {
    SEL viewSel = sel_registerName("leftSideBarDefaultEntranceView");
    SEL canShowSel = sel_registerName("canShowSideBarEntranceWithIdentification:");

    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;
    Class *classes = (Class *)malloc((unsigned long)count * sizeof(Class));
    if (!classes) return;
    count = objc_getClassList(classes, count);

    for (int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (directMethod(cls, viewSel)) {
            hookMethod(cls, viewSel, (IMP)compatSidebarViewHook);
        }
        if (directMethod(cls, canShowSel)) {
            hookMethod(cls, canShowSel, (IMP)compatSidebarCanShowHook);
        }
    }
    free(classes);
}


// -------- Targeted iPad long-press probe --------
// Reverse engineering of the uploaded AlphaPro build pinned its iPad media
// trigger to AWEPlayInteractionViewController:
//   - viewDidLoad     -> installs/retries the recognizer
//   - viewDidAppear:  -> installs/retries the recognizer
//   - showDislikeOnVideo is the native action AlphaPro intercepts when it has
//     a resolved AWEAwemeModel.
//
// v0.3-probe deliberately DOES NOT port AlphaPro's model resolver, custom
// panel, NSURLSession downloader, or save pipeline. A single long press only
// sends showDislikeOnVideo to the controller. This tells us what AwemeX 2.6.2
// already has downstream on the device:
//   * If AwemeX's own enhanced/media menu appears, the trigger bridge is enough.
//   * If only the stock dislike/not-interested UI appears, the original AwemeX
//     media panel is NOT downstream of this selector and more reversing is
//     required before a final long-press implementation.

static void compatAwemeLongPressAction(id self, SEL _cmd, id recognizer) {
    (void)_cmd;
    if (!self || !recognizer) return;

    SEL stateSel = sel_registerName("state");
    long state = ((long (*)(id, SEL))objc_msgSend)(recognizer, stateSel);
    if (state != 1) return; // UIGestureRecognizerStateBegan

    if (!objectResponds(self, "showDislikeOnVideo")) return;
    SEL actionSel = sel_registerName("showDislikeOnVideo");
    ((void (*)(id, SEL))objc_msgSend)(self, actionSel);
}

static BOOL ensureLongPressProbe(id controller) {
    if (!controller) return 0;

    id view = sendId0(controller, "view");
    if (!view) return 0;

    id existing = objc_getAssociatedObject(view, &gLongPressRecognizerKey);
    if (existing) return 1;

    Class lpClass = objc_getClass("UILongPressGestureRecognizer");
    if (!lpClass) return 0;

    SEL actionSel = sel_registerName("awx_ipadCompatLongPressProbe:");
    Class controllerClass = object_getClass(controller);
    if (!controllerClass) return 0;

    // Add the target-action method only to the concrete controller class.
    if (!class_getInstanceMethod(controllerClass, actionSel)) {
        if (!class_addMethod(controllerClass, actionSel,
                             (IMP)compatAwemeLongPressAction, "v@:@")) {
            if (!class_getInstanceMethod(controllerClass, actionSel)) return 0;
        }
    }

    SEL allocSel = sel_registerName("alloc");
    SEL initSel = sel_registerName("initWithTarget:action:");
    id recognizer = ((id (*)(id, SEL))objc_msgSend)((id)lpClass, allocSel);
    if (!recognizer) return 0;
    recognizer = ((id (*)(id, SEL, id, SEL))objc_msgSend)(recognizer, initSel,
                                                          controller, actionSel);
    if (!recognizer) return 0;

    // Match the useful parts of AlphaPro's targeted recognizer setup without
    // carrying its gesture-delegate arbitration or downloader. Keeping the
    // probe simple makes its device result unambiguous.
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(recognizer,
        sel_registerName("setNumberOfTouchesRequired:"), (NSUInteger)1);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(recognizer,
        sel_registerName("setCancelsTouchesInView:"), 1);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(recognizer,
        sel_registerName("setDelaysTouchesBegan:"), 0);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(recognizer,
        sel_registerName("setDelaysTouchesEnded:"), 0);

    ((void (*)(id, SEL, id))objc_msgSend)(view,
        sel_registerName("addGestureRecognizer:"), recognizer);
    objc_setAssociatedObject(view, &gLongPressRecognizerKey, recognizer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_release(recognizer); // view + association retain it
    return 1;
}

static void compatAwemeViewDidLoadHook(id self, SEL _cmd) {
    IMP original = findOriginal(self, _cmd, (IMP)compatAwemeViewDidLoadHook);
    if (original) ((void (*)(id, SEL))original)(self, _cmd);
    ensureLongPressProbe(self);
}

static void compatAwemeViewDidAppearHook(id self, SEL _cmd, BOOL animated) {
    IMP original = findOriginal(self, _cmd, (IMP)compatAwemeViewDidAppearHook);
    if (original) ((void (*)(id, SEL, BOOL))original)(self, _cmd, animated);
    ensureLongPressProbe(self);
}

static BOOL installLongPressProbe(void) {
    Class cls = objc_getClass("AWEPlayInteractionViewController");
    if (!cls) return 0;

    BOOL a = hookMethod(cls, sel_registerName("viewDidLoad"),
                        (IMP)compatAwemeViewDidLoadHook);
    BOOL b = hookMethod(cls, sel_registerName("viewDidAppear:"),
                        (IMP)compatAwemeViewDidAppearHook);
    return a || b;
}

static void installHooks(void *context);

static void retryHooks(void *context) {
    (void)context;
    installHooks(NULL);
}

static void installHooks(void *context) {
    (void)context;
    if (!isPad()) return;

    if (!gInstalledSearchA) {
        gInstalledSearchA = installSearchClass("AWESearchEntranceView");
    }
    if (!gInstalledSearchB) {
        gInstalledSearchB = installSearchClass("AWEHPDiscoverFeedEntranceView");
    }

    // Right-side iPad stack views observed in AlphaPro. These hooks only bridge
    // into AwemeX's own `awe_applySafeScaling`; no AlphaPro ax_scale preference.
    if (!gInstalledRightStackA) {
        gInstalledRightStackA = installRightStackClass("AWEElementStackView");
    }
    if (!gInstalledRightStackB) {
        gInstalledRightStackB = installRightStackClass("IESLiveStackView");
    }

    // Diagnostic only: targeted iPad media trigger probe on the exact controller
    // used by AlphaPro. No global UIView hook and no duplicate downloader.
    if (!gInstalledLongPressProbe) {
        gInstalledLongPressProbe = installLongPressProbe();
    }

    installSidebarHooks();

    // One-shot delayed retry only. No repeating timer/poll loop.
    if ((!gInstalledSearchA || !gInstalledSearchB ||
         !gInstalledRightStackA || !gInstalledRightStackB ||
         !gInstalledLongPressProbe) && !gRetryScheduled) {
        gRetryScheduled = 1;
        dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, 2LL * NSEC_PER_SEC),
                         dispatch_get_main_queue(), NULL, retryHooks);
    }
}

__attribute__((constructor))
static void AwemeX_iPadCompat_Init(void) {
    // Run after the current initializer wave so AwemeX's own hooks sit below ours.
    dispatch_async_f(dispatch_get_main_queue(), NULL, installHooks);
}
