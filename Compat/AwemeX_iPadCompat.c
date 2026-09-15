// AwemeX_iPadCompat v1.2
// Runtime-only iPad compatibility layer for AwemeX 2.6.2.
//
// Final iPad bridges in this file are deliberately narrow:
//   * top-right search: reuse AwemeX 2.6.2's native 0..1 opacity preference,
//     but apply it to the entrance imageView (not the hit-test container);
//   * right interaction stack: reuse AwemeX 2.6.2's native 50..60 scale value,
//     but apply the natural stack transform used by the iPad AlphaPro build;
//   * sidebar compatibility and the existing targeted long-press probe remain.
//
// No global UIView hooks, no repeating timers, no downloader/network code.
// Intentionally avoids private SDK headers. Theos can link this as a normal dylib.
#include <dispatch/dispatch.h>
#include <CoreGraphics/CGAffineTransform.h>
#include <CoreGraphics/CGGeometry.h>


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

// AwemeX 2.6.2 MyDefaults selectors recovered from the original dylib.
// Types from Objective-C metadata:
//   g24...:                       -> BOOL(id key)
//   KgzsTJEZJr3mvMOvq4Oa3MR     -> float   (右上角搜索透明度, UI range 0..1)
//   Jtznf5OncDO9R17VhoYb        -> float   (右侧按钮缩放比例度, UI range 50..60)
static const char *kMyDefaultsBoolGetter = "g24MPeX47iRQ9mJBhaKvZx6F:";
static const char *kNativeSearchAlphaGetter = "KgzsTJEZJr3mvMOvq4Oa3MR";
static const char *kNativeRightScaleGetter = "Jtznf5OncDO9R17VhoYb";

// UTF-8 preference keys used by AwemeX. Hex escapes avoid source-encoding issues.
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

static float awxNativeFloat0(const char *selectorName, float fallback) {
    if (!selectorName) return fallback;

    Class defaults = objc_getClass("MyDefaults");
    if (!defaults) return fallback;

    SEL getter = sel_registerName(selectorName);
    if (!class_getClassMethod(defaults, getter)) return fallback;

    return ((float (*)(id, SEL))objc_msgSend)((id)defaults, getter);
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


// -------- Native search opacity + natural right-stack bridge --------

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

static double clampDouble(double value, double lo, double hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}

// The original 2.6.2 implementation hooks -imageView, applies the value from
// +[MyDefaults KgzsTJEZJr3mvMOvq4Oa3MR] directly with setAlpha:, and then
// enables interaction. Applying alpha to the imageView rather than the entrance
// container is critical: alpha==0 must not remove the parent's hit target.
static double nativeSearchVisualAlpha(void) {
    double alpha = (double)awxNativeFloat0(kNativeSearchAlphaGetter, 1.0f);
    alpha = clampDouble(alpha, 0.0, 1.0);

    return alpha;
}

static void applyNativeSearchVisual(id entrance) {
    if (!entrance) return;

    // Keep the hit-test container active regardless of visual alpha.
    if (objectResponds(entrance, "setUserInteractionEnabled:")) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            entrance, sel_registerName("setUserInteractionEnabled:"), 1);
    }

    if (!objectResponds(entrance, "imageView")) return;
    id imageView = sendId0(entrance, "imageView");
    if (!imageView) return;

    double alpha = nativeSearchVisualAlpha();
    ((void (*)(id, SEL, double))objc_msgSend)(
        imageView, sel_registerName("setAlpha:"), alpha);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        imageView, sel_registerName("setUserInteractionEnabled:"), 1);
}

// Restrict scaling to the right interaction stack. Class identity alone is not
// enough because AWEElementStackView/IESLiveStackView are reused elsewhere.
static BOOL compatStringEqualsUTF8(id stringObject, const char *utf8) {
    if (!stringObject || !utf8) return 0;
    id other = makeNSString(utf8);
    if (!other) return 0;
    return ((BOOL (*)(id, SEL, id))objc_msgSend)(
        stringObject, sel_registerName("isEqualToString:"), other);
}

static BOOL compatIsKindOfClassName(id object, const char *className) {
    if (!object || !className) return 0;
    Class cls = objc_getClass(className);
    if (!cls) return 0;
    return ((BOOL (*)(id, SEL, Class))objc_msgSend)(
        object, sel_registerName("isKindOfClass:"), cls);
}

static NSUInteger compatSubviewCount(id view) {
    id subviews = sendId0(view, "subviews");
    if (!subviews) return 0;
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(
        subviews, sel_registerName("count"));
}

static BOOL compatContainsSubviewOfClassName(id container, const char *className) {
    if (!container || !className) return 0;
    id subviews = sendId0(container, "subviews");
    if (!subviews) return 0;

    NSUInteger count = ((NSUInteger (*)(id, SEL))objc_msgSend)(
        subviews, sel_registerName("count"));
    for (NSUInteger i = 0; i < count; i++) {
        id sub = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
            subviews, sel_registerName("objectAtIndex:"), i);
        if (!sub) continue;
        if (compatIsKindOfClassName(sub, className)) return 1;
        if (compatContainsSubviewOfClassName(sub, className)) return 1;
    }
    return 0;
}

static BOOL compatStackHasElementClassName(id container, const char *targetName) {
    if (!container || !targetName) return 0;
    id subviews = sendId0(container, "subviews");
    if (!subviews) return 0;

    NSUInteger count = ((NSUInteger (*)(id, SEL))objc_msgSend)(
        subviews, sel_registerName("count"));
    for (NSUInteger i = 0; i < count; i++) {
        id sub = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
            subviews, sel_registerName("objectAtIndex:"), i);
        if (!sub) continue;

        if (objectResponds(sub, "elementClassName")) {
            id name = sendId0(sub, "elementClassName");
            if (compatStringEqualsUTF8(name, targetName)) return 1;
        }
        if (compatStackHasElementClassName(sub, targetName)) return 1;
    }
    return 0;
}

static BOOL compatWindowFrame(id view, CGRect *outFrame, double *outW, double *outH) {
    if (!view || !outFrame || !outW || !outH) return 0;
    id superview = sendId0(view, "superview");
    id window = sendId0(view, "window");
    if (!superview || !window) return 0;

    CGRect frame = ((CGRect (*)(id, SEL))objc_msgSend)(
        view, sel_registerName("frame"));
    CGRect converted = ((CGRect (*)(id, SEL, CGRect, id))objc_msgSend)(
        superview, sel_registerName("convertRect:toView:"), frame, window);

    Class screenClass = objc_getClass("UIScreen");
    if (!screenClass) return 0;
    id screen = ((id (*)(id, SEL))objc_msgSend)(
        (id)screenClass, sel_registerName("mainScreen"));
    if (!screen) return 0;
    CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(
        screen, sel_registerName("bounds"));

    if (converted.size.width <= 0.0 || converted.size.height <= 0.0 ||
        bounds.size.width <= 0.0 || bounds.size.height <= 0.0) {
        return 0;
    }

    *outFrame = converted;
    *outW = (double)bounds.size.width;
    *outH = (double)bounds.size.height;
    return 1;
}

// Exact geometry fallback from the user's working iPad AlphaPro implementation.
// It is needed because some iPad builds expose neither the right label nor the
// avatar element on the interaction stack.
static BOOL compatIsLooseRightAreaStack(id view) {
    if (!view || !sendId0(view, "superview")) return 0;
    if (compatIsKindOfClassName(view, "UIScrollView")) return 0;

    CGRect f;
    double screenW = 0.0, screenH = 0.0;
    if (!compatWindowFrame(view, &f, &screenW, &screenH)) return 0;

    if ((double)f.origin.x < screenW * 0.55) return 0;
    if ((double)f.origin.y < screenH * 0.22) return 0;
    double maxWidth = screenW * 0.34;
    if (maxWidth > 260.0) maxWidth = 260.0;
    if ((double)f.size.width > maxWidth) return 0;
    if ((double)f.size.height < 90.0 ||
        (double)f.size.height > screenH * 0.82) return 0;
    if (compatSubviewCount(view) < 2) return 0;
    return 1;
}

static BOOL isRightStackCompat(id view) {
    if (!view) return 0;

    id label = sendId0(view, "accessibilityLabel");
    if (compatStringEqualsUTF8(label, "right")) return 1;
    if (compatContainsSubviewOfClassName(
            view, "AWEPlayInteractionUserAvatarView")) return 1;
    if (compatStackHasElementClassName(
            view, "AWEPlayInteractionUserAvatarOptElementElement")) return 1;

    return compatIsLooseRightAreaStack(view);
}

// AwemeX 2.6.2 exposes this slider as 50..60. The phone implementation does:
//     scale = clamp(raw / bounds.width * 0.64, 0.30, 1.20)
// so a wider iPad stack is divided by a much larger width and collapses.
// At the native 60-point maximum, the intended visual width is 60*0.64=38.4pt.
// Normalize against that native maximum instead: 50..60 -> 0.8333..1.0.
// This keeps the original slider's ordering/range while making the response
// independent of the iPad stack's much wider bounds.
static double nativeRightStackScale(void) {
    double raw = (double)awxNativeFloat0(kNativeRightScaleGetter, -1.0f);
    if (raw <= 0.0) return 1.0;
    raw = clampDouble(raw, 50.0, 60.0);
    return raw / 60.0;
}

static CGAffineTransform rightStackTargetTransform(id view) {
    double scale = nativeRightStackScale();
    double delta = scale - 1.0;
    if (delta < 0.0) delta = -delta;
    if (scale <= 0.0 || delta <= 0.001) {
        return CGAffineTransformMake(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
    }

    double ty = 0.0;
    id subviews = sendId0(view, "subviews");
    if (subviews) {
        NSUInteger count = ((NSUInteger (*)(id, SEL))objc_msgSend)(
            subviews, sel_registerName("count"));
        for (NSUInteger i = 0; i < count; i++) {
            id sub = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
                subviews, sel_registerName("objectAtIndex:"), i);
            if (!sub) continue;
            CGRect subFrame = ((CGRect (*)(id, SEL))objc_msgSend)(
                sub, sel_registerName("frame"));
            double h = (double)subFrame.size.height;
            ty += (h - h * scale) / 2.0;
        }
    }

    CGRect frame = ((CGRect (*)(id, SEL))objc_msgSend)(
        view, sel_registerName("frame"));
    double width = (double)frame.size.width;
    double rightTX = (width - width * scale) / 2.0;

    return CGAffineTransformMake(
        (CGFloat)scale, 0.0, 0.0, (CGFloat)scale,
        (CGFloat)rightTX, (CGFloat)ty);
}

static double absDouble(double v) { return v < 0.0 ? -v : v; }

static BOOL transformsNearlyEqual(CGAffineTransform a, CGAffineTransform b) {
    const double e = 0.0005;
    return absDouble((double)a.a - (double)b.a) <= e &&
           absDouble((double)a.b - (double)b.b) <= e &&
           absDouble((double)a.c - (double)b.c) <= e &&
           absDouble((double)a.d - (double)b.d) <= e &&
           absDouble((double)a.tx - (double)b.tx) <= e &&
           absDouble((double)a.ty - (double)b.ty) <= e;
}

static void applyRightStackTarget(id view) {
    if (!view || !isRightStackCompat(view)) return;
    CGAffineTransform target = rightStackTargetTransform(view);
    CGAffineTransform current = ((CGAffineTransform (*)(id, SEL))objc_msgSend)(
        view, sel_registerName("transform"));
    if (transformsNearlyEqual(current, target)) return;
    ((void (*)(id, SEL, CGAffineTransform))objc_msgSend)(
        view, sel_registerName("setTransform:"), target);
}

static void compatRightStackVoidHook(id self, SEL _cmd) {
    IMP original = findOriginal(self, _cmd, (IMP)compatRightStackVoidHook);
    if (original) ((void (*)(id, SEL))original)(self, _cmd);
    if (sendId0(self, "window")) applyRightStackTarget(self);
}

static id compatRightStackArrangedSubviewsHook(id self, SEL _cmd) {
    IMP original = findOriginal(
        self, _cmd, (IMP)compatRightStackArrangedSubviewsHook);
    id result = original ? ((id (*)(id, SEL))original)(self, _cmd) : NULL;
    if (sendId0(self, "window")) applyRightStackTarget(self);
    return result;
}

static void compatRightStackSetTransformHook(
    id self, SEL _cmd, CGAffineTransform incoming) {
    IMP original = findOriginal(
        self, _cmd, (IMP)compatRightStackSetTransformHook);
    if (!original) return;

    if (isRightStackCompat(self)) {
        CGAffineTransform target = rightStackTargetTransform(self);
        ((void (*)(id, SEL, CGAffineTransform))original)(self, _cmd, target);
        return;
    }
    ((void (*)(id, SEL, CGAffineTransform))original)(self, _cmd, incoming);
}

static BOOL installRightStackClass(const char *className) {
    Class cls = objc_getClass(className);
    if (!cls) return 0;

    BOOL a = hookMethod(cls, sel_registerName("layoutSubviews"),
                        (IMP)compatRightStackVoidHook);
    BOOL b = hookMethod(cls, sel_registerName("didMoveToWindow"),
                        (IMP)compatRightStackVoidHook);
    BOOL c = hookMethod(cls, sel_registerName("arrangedSubviews"),
                        (IMP)compatRightStackArrangedSubviewsHook);
    BOOL d = hookMethod(cls, sel_registerName("setTransform:"),
                        (IMP)compatRightStackSetTransformHook);
    (void)a; (void)b; (void)c;
    // setTransform: is the essential guard; lifecycle hooks are refresh helpers.
    return d;
}

static id compatSearchImageViewHook(id self, SEL _cmd) {
    IMP original = findOriginal(self, _cmd, (IMP)compatSearchImageViewHook);
    id imageView = original ? ((id (*)(id, SEL))original)(self, _cmd) : NULL;
    if (imageView) {
        double alpha = nativeSearchVisualAlpha();
        ((void (*)(id, SEL, double))objc_msgSend)(
            imageView, sel_registerName("setAlpha:"), alpha);
        ((void (*)(id, SEL, BOOL))objc_msgSend)(
            imageView, sel_registerName("setUserInteractionEnabled:"), 1);
    }
    return imageView;
}

static void compatSearchVoidHook(id self, SEL _cmd) {
    IMP original = findOriginal(self, _cmd, (IMP)compatSearchVoidHook);
    if (original) ((void (*)(id, SEL))original)(self, _cmd);
    applyNativeSearchVisual(self);
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

    // 2.6.2's original implementation hooks -imageView. Keep lifecycle hooks
    // too, because iPad relayouts may replace/reset the image view afterwards.
    BOOL a = hookMethod(cls, sel_registerName("imageView"),
                        (IMP)compatSearchImageViewHook);
    BOOL b = hookMethod(cls, sel_registerName("layoutSubviews"),
                        (IMP)compatSearchVoidHook);
    BOOL c = hookMethod(cls, sel_registerName("didMoveToWindow"),
                        (IMP)compatSearchVoidHook);
    (void)b; (void)c;
    // imageView is the exact 2.6.2 rendering path. Do not mark this class as
    // installed merely because a generic lifecycle method was hookable.
    return a;
}

static void installSearchHooksIfNeeded(void) {
    if (!gInstalledSearchA) {
        gInstalledSearchA = installSearchClass("AWESearchEntranceView");
    }
    if (!gInstalledSearchB) {
        gInstalledSearchB = installSearchClass("AWEHPDiscoverFeedEntranceView");
    }
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
    // Feed classes may live in a lazily loaded image; retry search hook install
    // when the actual play controller comes alive instead of polling UIView.
    installSearchHooksIfNeeded();
    ensureLongPressProbe(self);
}

static void compatAwemeViewDidAppearHook(id self, SEL _cmd, BOOL animated) {
    IMP original = findOriginal(self, _cmd, (IMP)compatAwemeViewDidAppearHook);
    if (original) ((void (*)(id, SEL, BOOL))original)(self, _cmd, animated);
    installSearchHooksIfNeeded();
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

    installSearchHooksIfNeeded();

    // Right-side iPad stack views: native 2.6.2 scale value + the user's
    // natural iPad stack transform. No cumulative safe-scaling bridge.
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
