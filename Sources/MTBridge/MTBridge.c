#include "MTBridge.h"
#include <dlfcn.h>
#include <stdio.h>
#include <CoreFoundation/CoreFoundation.h>

typedef int (*MTContactCallback)(MTDeviceRef, const MTTouch *, int, double, int);

static CFMutableArrayRef (*p_MTDeviceCreateList)(void);
static void (*p_MTRegisterContactFrameCallback)(MTDeviceRef, MTContactCallback);
static void (*p_MTUnregisterContactFrameCallback)(MTDeviceRef, MTContactCallback);
static int  (*p_MTDeviceStart)(MTDeviceRef, int);
static void (*p_MTDeviceStop)(MTDeviceRef);
static int  (*p_MTDeviceGetSensorSurfaceDimensions)(MTDeviceRef, int *, int *);
static bool (*p_MTDeviceIsBuiltIn)(MTDeviceRef);

static CFMutableArrayRef g_devices = NULL;
static MTBridgeTouchHandler g_handler = NULL;

static int frameCallback(MTDeviceRef device, const MTTouch *touches, int count, double timestamp, int frame) {
    if (g_handler) g_handler(device, touches, count, timestamp, frame);
    return 0;
}

bool MTBridgeLoad(void) {
    static void *handle = NULL;
    if (handle) return true;
    handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!handle) { fprintf(stderr, "MTBridge: dlopen failed: %s\n", dlerror()); return false; }
#define LOAD(sym) p_##sym = dlsym(handle, #sym); if (!p_##sym) { fprintf(stderr, "MTBridge: missing %s\n", #sym); }
    LOAD(MTDeviceCreateList)
    LOAD(MTRegisterContactFrameCallback)
    LOAD(MTUnregisterContactFrameCallback)
    LOAD(MTDeviceStart)
    LOAD(MTDeviceStop)
    LOAD(MTDeviceGetSensorSurfaceDimensions)
    LOAD(MTDeviceIsBuiltIn)
#undef LOAD
    return p_MTDeviceCreateList && p_MTRegisterContactFrameCallback && p_MTDeviceStart && p_MTDeviceStop;
}

int MTBridgeStart(MTBridgeTouchHandler handler) {
    if (!MTBridgeLoad()) return 0;
    MTBridgeStop();
    g_handler = handler;
    g_devices = p_MTDeviceCreateList();
    if (!g_devices) return 0;
    CFIndex n = CFArrayGetCount(g_devices);
    int started = 0;
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, i);
        p_MTRegisterContactFrameCallback(dev, frameCallback);
        if (p_MTDeviceStart(dev, 0) == 0) started++;
    }
    return started;
}

void MTBridgeStop(void) {
    if (!g_devices) return;
    CFIndex n = CFArrayGetCount(g_devices);
    for (CFIndex i = 0; i < n; i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, i);
        if (p_MTUnregisterContactFrameCallback) p_MTUnregisterContactFrameCallback(dev, frameCallback);
        p_MTDeviceStop(dev);
    }
    CFRelease(g_devices);
    g_devices = NULL;
    g_handler = NULL;
}

void MTBridgeSurfaceSizeMM(MTDeviceRef device, double *width, double *height) {
    int w = 0, h = 0;
    if (p_MTDeviceGetSensorSurfaceDimensions && p_MTDeviceGetSensorSurfaceDimensions(device, &w, &h) == 0) {
        *width = w / 100.0;  // reported in hundredths of a millimetre
        *height = h / 100.0;
    } else { *width = 0; *height = 0; }
}

bool MTBridgeIsBuiltIn(MTDeviceRef device) {
    return p_MTDeviceIsBuiltIn ? p_MTDeviceIsBuiltIn(device) : true;
}
