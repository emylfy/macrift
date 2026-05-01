// space-switcher — instant macOS space switching.
//
// One-shot CLI:  space-switcher left|right
//                Posts a synthetic Dock swipe gesture (progress = ±FLT_TRUE_MIN
//                with high velocity). macOS interprets this as "swipe almost
//                completed" and skips the animation.
//
// Daemon mode:   space-switcher --daemon
//                Installs a CGEventTap intercepting Ctrl+←/→ (no other
//                modifiers). When the user presses them, the event is
//                swallowed and replaced with our instant gesture — macOS
//                native handler never sees it, so no slow animation.
//
// Bounds checking via private CGS symbols (weak-imported, degrades silently).

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <float.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// CGEvent fields observed in real Dock swipe gestures.
// See iss-switcher (jurplel/InstantSpaceSwitcher) for field discovery.
enum {
    F_TYPE     = 55,   // CGSEventType  → kCGSEventDockControl (30)
    F_HID_TYPE = 110,  //                → kIOHIDEventTypeDockSwipe (23)
    F_MOTION   = 123,  //                → horizontal (1)
    F_PROGRESS = 124,
    F_VEL_X    = 129,
    F_VEL_Y    = 130,
    F_PHASE    = 132,  // 1=Began, 2=Changed, 4=Ended
};

// Private CGS symbols used for bounds checking (current space index + total).
// Weak-imported: if Apple ever removes them, bounds-check disables silently
// and we fall back to "post anyway" (causing the bounce-back animation at edges).
typedef int32_t  CGSConnectionID;
typedef uint64_t CGSSpaceID;
extern CGSConnectionID CGSMainConnectionID(void) __attribute__((weak_import));
extern CGSSpaceID CGSGetActiveSpace(CGSConnectionID) __attribute__((weak_import));
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID, CFStringRef) __attribute__((weak_import));

// Resolve current space index and total space count for the active display.
// Returns false if private symbols missing or query fails.
static bool get_space_info(unsigned int *out_curr, unsigned int *out_total) {
    if (!CGSMainConnectionID || !CGSGetActiveSpace || !CGSCopyManagedDisplaySpaces) return false;

    CGSConnectionID cid = CGSMainConnectionID();
    if (cid == 0) return false;
    CGSSpaceID active = CGSGetActiveSpace(cid);
    if (active == 0) return false;

    CFArrayRef displays = CGSCopyManagedDisplaySpaces(cid, NULL);
    if (!displays) return false;

    bool found = false;
    for (CFIndex d = 0, dn = CFArrayGetCount(displays); d < dn && !found; d++) {
        CFDictionaryRef display = (CFDictionaryRef)CFArrayGetValueAtIndex(displays, d);
        if (!display || CFGetTypeID(display) != CFDictionaryGetTypeID()) continue;

        CFArrayRef spaces = (CFArrayRef)CFDictionaryGetValue(display, CFSTR("Spaces"));
        if (!spaces || CFGetTypeID(spaces) != CFArrayGetTypeID()) continue;

        CFIndex sn = CFArrayGetCount(spaces);
        for (CFIndex s = 0; s < sn; s++) {
            CFDictionaryRef space = (CFDictionaryRef)CFArrayGetValueAtIndex(spaces, s);
            if (!space || CFGetTypeID(space) != CFDictionaryGetTypeID()) continue;

            CFNumberRef sid_num = (CFNumberRef)CFDictionaryGetValue(space, CFSTR("id64"));
            if (!sid_num) continue;

            CGSSpaceID sid = 0;
            CFNumberGetValue(sid_num, kCFNumberSInt64Type, &sid);
            if (sid == active) {
                *out_curr  = (unsigned int)s;
                *out_total = (unsigned int)sn;
                found = true;
                break;
            }
        }
    }
    CFRelease(displays);
    return found;
}

static void post_phase(int phase, double progress, double vel) {
    CGEventRef ev = CGEventCreate(NULL);
    if (!ev) return;
    CGEventSetIntegerValueField(ev, F_TYPE,     30);
    CGEventSetIntegerValueField(ev, F_HID_TYPE, 23);
    CGEventSetIntegerValueField(ev, F_PHASE,    phase);
    CGEventSetIntegerValueField(ev, F_MOTION,   1);
    CGEventSetDoubleValueField (ev, F_PROGRESS, progress);
    CGEventSetDoubleValueField (ev, F_VEL_X,    vel);
    CGEventSetDoubleValueField (ev, F_VEL_Y,    vel);
    CGEventPost(kCGSessionEventTap, ev);
    CFRelease(ev);
}

static void switch_space(int dir) {
    unsigned int curr = 0, total = 0;
    if (get_space_info(&curr, &total)) {
        if (dir < 0 && curr == 0)            return;  // already leftmost
        if (dir > 0 && curr + 1 >= total)    return;  // already rightmost
    }

    double progress = dir > 0 ? (double)FLT_TRUE_MIN : -(double)FLT_TRUE_MIN;
    double vel      = dir > 0 ? 2000.0 : -2000.0;

    // Spread phases across ~16ms (one frame at 60Hz). Posting all three back-to-back
    // can leave the Dock stuck in mid-gesture state and freeze mouse input.
    post_phase(1, progress, vel);
    usleep(8000);
    post_phase(2, progress, vel);
    usleep(8000);
    post_phase(4, progress, vel);

    // Let WindowServer drain our events before the process exits.
    usleep(50000);
}

// MARK: - Daemon (event tap intercepting Ctrl+arrow)

static CFMachPortRef g_tap = NULL;

static CGEventRef tap_callback(CGEventTapProxy proxy, CGEventType type,
                               CGEventRef event, void *refcon) {
    (void)proxy; (void)refcon;

    // The tap can be disabled by the system (timeout, user input). Re-enable.
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (g_tap) CGEventTapEnable(g_tap, true);
        return event;
    }

    if (type != kCGEventKeyDown) return event;

    CGEventFlags flags = CGEventGetFlags(event);
    bool ctrl  = (flags & kCGEventFlagMaskControl) != 0;
    bool other = (flags & (kCGEventFlagMaskCommand
                         | kCGEventFlagMaskAlternate
                         | kCGEventFlagMaskShift)) != 0;
    if (!ctrl || other) return event;  // need Ctrl alone

    int64_t kc = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    if (kc == 123) { switch_space(-1); return NULL; }  // ← left arrow
    if (kc == 124) { switch_space(+1); return NULL; }  // → right arrow
    return event;
}

static int run_daemon(void) {
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown);
    g_tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                             kCGEventTapOptionDefault, mask, tap_callback, NULL);
    if (!g_tap) {
        fprintf(stderr, "space-switcher: failed to create event tap\n"
                        "  → grant Accessibility in System Settings\n");
        return 1;
    }
    CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, g_tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
    CGEventTapEnable(g_tap, true);
    fprintf(stderr, "space-switcher: daemon started (Ctrl+←/→ intercept)\n");
    CFRunLoopRun();
    return 0;
}

// MARK: - Main

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s left|right | --daemon\n", argv[0]);
        return 2;
    }
    if (!strcmp(argv[1], "--daemon")) return run_daemon();
    if (argc != 2) {
        fprintf(stderr, "Usage: %s left|right | --daemon\n", argv[0]);
        return 2;
    }
    if      (!strcmp(argv[1], "left")  || !strcmp(argv[1], "l")) switch_space(-1);
    else if (!strcmp(argv[1], "right") || !strcmp(argv[1], "r")) switch_space(+1);
    else { fprintf(stderr, "Usage: %s left|right | --daemon\n", argv[0]); return 2; }
    return 0;
}
