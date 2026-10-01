#include "CMultitouch.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>

_Static_assert(sizeof(MTTouch) == 96, "MTTouch layout must match MultitouchSupport");

typedef CFMutableArrayRef (*CreateListFn)(void);
typedef void (*RegisterFn)(MTDeviceRef, MTContactCallback);
typedef void (*StartFn)(MTDeviceRef, int);
typedef void (*StopFn)(MTDeviceRef);
typedef int (*SizeFn)(MTDeviceRef, int32_t *, int32_t *);

static void *gHandle;
static CreateListFn gCreateList;
static RegisterFn gRegister;
static RegisterFn gUnregister;
static StartFn gStart;
static StopFn gStop;
static SizeFn gSize;

static CFMutableArrayRef gDevices;
static MTContactCallback gCallback;

static int load(void) {
    if (gHandle) return 1;
    gHandle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!gHandle) return 0;

    gCreateList = (CreateListFn)dlsym(gHandle, "MTDeviceCreateList");
    gRegister = (RegisterFn)dlsym(gHandle, "MTRegisterContactFrameCallback");
    gUnregister = (RegisterFn)dlsym(gHandle, "MTUnregisterContactFrameCallback");
    gStart = (StartFn)dlsym(gHandle, "MTDeviceStart");
    gStop = (StopFn)dlsym(gHandle, "MTDeviceStop");
    gSize = (SizeFn)dlsym(gHandle, "MTDeviceGetSensorSurfaceDimensions");

    if (!gCreateList || !gRegister || !gStart) {
        dlclose(gHandle);
        gHandle = NULL;
        return 0;
    }
    return 1;
}

int MTBridgeStart(MTContactCallback callback) {
    if (!load()) return -1;
    MTBridgeStop();

    gDevices = gCreateList();
    if (!gDevices) return 0;
    gCallback = callback;

    CFIndex count = CFArrayGetCount(gDevices);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(gDevices, i);
        gRegister(device, callback);
        gStart(device, 0);
    }
    return (int)count;
}

void MTBridgeStop(void) {
    if (!gDevices) return;
    CFIndex count = CFArrayGetCount(gDevices);
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(gDevices, i);
        if (gUnregister) gUnregister(device, gCallback);
        if (gStop) gStop(device);
    }
    CFRelease(gDevices);
    gDevices = NULL;
    gCallback = NULL;
}

int MTBridgeSurfaceSize(MTDeviceRef device, int32_t *width, int32_t *height) {
    if (!load() || !gSize || !device) return 0;
    *width = 0;
    *height = 0;
    gSize(device, width, height);
    return *width > 0 && *height > 0;
}
