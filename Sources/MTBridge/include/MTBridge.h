#ifndef MTBridge_h
#define MTBridge_h
#include <stdbool.h>
#include <stdint.h>

// Layout of the private MultitouchSupport contact record.
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTReadout;

typedef struct {
    int32_t  frame;
    double   timestamp;
    int32_t  identifier;
    int32_t  state;          // 1 start, 2 hover, 3 make touch, 4 touching, 5 break, 6 linger, 7 leave
    int32_t  fingerID;
    int32_t  handID;
    MTReadout normalized;    // 0..1, origin bottom-left
    float    size;           // pressure-ish contact size
    int32_t  zero1;
    float    angle;
    float    majorAxis;
    float    minorAxis;
    MTReadout absolute;      // millimetres
    int32_t  zero2[2];
    float    density;
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTBridgeTouchHandler)(MTDeviceRef device, const MTTouch *touches, int count, double timestamp, int frame);

// Loads MultitouchSupport at runtime. Returns false if the framework is unavailable.
bool MTBridgeLoad(void);
// Starts every attached multitouch device, delivering frames to `handler`.
int  MTBridgeStart(MTBridgeTouchHandler handler);
void MTBridgeStop(void);
// Sensor size of the device in millimetres (0 if unknown).
void MTBridgeSurfaceSizeMM(MTDeviceRef device, double *width, double *height);
bool MTBridgeIsBuiltIn(MTDeviceRef device);

#endif
