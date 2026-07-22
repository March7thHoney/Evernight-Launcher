#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define DYLD_INTERPOSE(replacement, replacee) \
    __attribute__((used)) static struct { \
        const void *replacement; \
        const void *replacee; \
    } interpose_##replacee __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)(unsigned long)&replacement, \
        (const void *)(unsigned long)&replacee \
    }

static CGError keep_mouse_associated(boolean_t connected) {
    return kCGErrorSuccess;
}

static CGError ignore_cursor_warp(CGPoint point) {
    return kCGErrorSuccess;
}

static void ignore_void(id self, SEL command) {}
static void ignore_event(id self, SEL command, NSEvent *event) {}
static void ignore_rect(id self, SEL command, CGRect rect) {}
static BOOL ignore_point(id self, SEL command, CGPoint point) { return NO; }
static void force_arrow_cursor(id self, SEL command, BOOL force) { [[NSCursor arrowCursor] set]; }

static void replace_instance_method(Class target, const char *name, IMP replacement) {
    SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(target, selector);
    if (method) class_replaceMethod(target, selector, replacement, method_getTypeEncoding(method));
}

static void install_cursor_overrides(void) {
    BOOL aggressive = getenv("EVERNIGHT_CURSOR_RELEASE_AGGRESSIVE") != NULL;
    Class cursor_meta = object_getClass(NSCursor.class);
    replace_instance_method(cursor_meta, "hide", (IMP)ignore_void);

    for (int attempt = 0; attempt < 10000; attempt++) {
        Class controller = objc_lookUpClass("WineApplicationController");
        if (controller) {
            replace_instance_method(controller, "hideCursor", (IMP)ignore_void);
            replace_instance_method(controller, "startClippingCursor:", (IMP)ignore_rect);
            replace_instance_method(controller, "setCursorPosition:", (IMP)ignore_point);

            Class event_tap = objc_lookUpClass("WineEventTapClipCursorHandler");
            Class confinement = objc_lookUpClass("WineConfinementClipCursorHandler");
            if (event_tap) replace_instance_method(event_tap, "startClippingCursor:", (IMP)ignore_rect);
            if (confinement) replace_instance_method(confinement, "startClippingCursor:", (IMP)ignore_rect);
            if (aggressive) {
                replace_instance_method(controller, "handleMouseMove:", (IMP)ignore_event);
                replace_instance_method(controller, "updateCursor:", (IMP)force_arrow_cursor);
                dispatch_async(dispatch_get_main_queue(), ^{ [[NSCursor arrowCursor] set]; });
            }
            fprintf(stderr, "evernight-cursor-release: Wine cursor capture disabled (aggressive=%d)\n", aggressive);
            return;
        }
        usleep(1000);
    }
}

__attribute__((constructor)) static void start_cursor_override_install(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
        install_cursor_overrides();
    });
}

DYLD_INTERPOSE(keep_mouse_associated, CGAssociateMouseAndMouseCursorPosition);
DYLD_INTERPOSE(ignore_cursor_warp, CGWarpMouseCursorPosition);
