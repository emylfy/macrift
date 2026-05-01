// stillcolord — disable temporal dithering on Apple Silicon
// Headless daemon port of Stillcolor (https://github.com/aiaf/Stillcolor)
//
// Usage:
//   stillcolord            # daemon: apply + watch for display reconfig
//   stillcolord --apply    # one-shot disable, exit
//   stillcolord --enable   # one-shot re-enable, exit
//   stillcolord --status   # print enableDither value(s) and exit

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/IOKitLib.h>
#include <dispatch/dispatch.h>
#include <mach/mach_error.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static void set_dither(bool enabled) {
    io_iterator_t iter = IO_OBJECT_NULL;
    kern_return_t kr = IOServiceGetMatchingServices(
        kIOMainPortDefault,
        IOServiceMatching("IOMobileFramebufferAP"),
        &iter);
    if (kr != KERN_SUCCESS || iter == IO_OBJECT_NULL) {
        fprintf(stderr, "stillcolord: no IOMobileFramebufferAP services (Apple Silicon required)\n");
        return;
    }

    CFBooleanRef value = enabled ? kCFBooleanTrue : kCFBooleanFalse;
    char ts[32];
    time_t now = time(NULL);
    strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%S", localtime(&now));

    io_service_t svc;
    while ((svc = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        kern_return_t r = IORegistryEntrySetCFProperty(svc, CFSTR("enableDither"), value);
        fprintf(stderr, "[%s] stillcolord: enableDither=%s -> %s\n",
                ts, enabled ? "true" : "false", mach_error_string(r));
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);
}

static void print_status(void) {
    io_iterator_t iter = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
            IOServiceMatching("IOMobileFramebufferAP"), &iter) != KERN_SUCCESS
        || iter == IO_OBJECT_NULL) {
        fprintf(stderr, "error: no IOMobileFramebufferAP services\n");
        return;
    }

    int idx = 0;
    io_service_t svc;
    while ((svc = IOIteratorNext(iter)) != IO_OBJECT_NULL) {
        idx++;
        CFTypeRef dither = IORegistryEntrySearchCFProperty(svc, kIOServicePlane,
            CFSTR("enableDither"), kCFAllocatorDefault, 0);
        CFTypeRef external = IORegistryEntrySearchCFProperty(svc, kIOServicePlane,
            CFSTR("external"), kCFAllocatorDefault, 0);

        const char *loc = (external && CFGetTypeID(external) == CFBooleanGetTypeID()
                           && CFBooleanGetValue((CFBooleanRef)external)) ? "external" : "embedded";

        if (dither && CFGetTypeID(dither) == CFBooleanGetTypeID()) {
            printf("display %d (%s): enableDither=%s\n", idx, loc,
                   CFBooleanGetValue((CFBooleanRef)dither) ? "true" : "false");
        } else {
            printf("display %d (%s): enableDither=<unknown>\n", idx, loc);
        }

        if (dither) CFRelease(dither);
        if (external) CFRelease(external);
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);
}

static void display_callback(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *info) {
    (void)display; (void)info;
    if (flags & (kCGDisplayAddFlag | kCGDisplayRemoveFlag
                 | kCGDisplayEnabledFlag | kCGDisplayDisabledFlag)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                       dispatch_get_main_queue(),
                       ^{ set_dither(false); });
    }
}

int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "";

    if (!strcmp(mode, "--apply")) {
        set_dither(false);
        return 0;
    }
    if (!strcmp(mode, "--enable")) {
        set_dither(true);
        return 0;
    }
    if (!strcmp(mode, "--status")) {
        print_status();
        return 0;
    }
    if (mode[0] != 0 && strcmp(mode, "--daemon") != 0) {
        fprintf(stderr, "Usage: %s [--daemon|--apply|--enable|--status]\n", argv[0]);
        return 2;
    }

    set_dither(false);
    CGDisplayRegisterReconfigurationCallback(display_callback, NULL);
    CFRunLoopRun();
    return 0;
}
