#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <stdint.h>

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

/// One contact as delivered by MultitouchSupport.framework (private API, 96 bytes).
/// `normalized.position` is 0...1 on both axes with the origin at the bottom-left of the pad.
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    /// 0 not tracking, 1 start in range, 2 hover, 3 make touch, 4 touching, 5 break touch, 6 linger, 7 out of range.
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    MTVector normalized;
    float size;
    int32_t zero1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int32_t zero2[2];
    float density;
} MTTouch;

typedef void *MTDeviceRef;

typedef int (*MTContactCallback)(MTDeviceRef device, const MTTouch *touches, int32_t count, double timestamp, int32_t frame);

/// Loads the framework and starts every multitouch device (built-in trackpad, Magic Trackpad).
/// Returns the number of devices started, or -1 if the framework could not be loaded.
int MTBridgeStart(MTContactCallback callback);

/// Unregisters the callback and stops all devices started by MTBridgeStart.
void MTBridgeStop(void);

/// Sensor surface size in hundredths of a millimetre. Returns 0 if unavailable.
int MTBridgeSurfaceSize(MTDeviceRef device, int32_t *width, int32_t *height);

#endif
