#ifndef GLIDE_MULTITOUCH_BRIDGE_H
#define GLIDE_MULTITOUCH_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    float x;
    float y;
} GLDMTPoint;

typedef struct {
    GLDMTPoint position;
    GLDMTPoint velocity;
} GLDMTVector;

// Shared private-framework ABI used by the C trackpad bridge and Swift mouse
// provider. Keeping one layout prevents the two input paths from diverging.
typedef struct {
    int32_t frame;
    int32_t padding;
    double timestamp;
    int32_t identifier;
    int32_t state;
    int32_t finger_id;
    int32_t hand_id;
    GLDMTVector normalized;
    float size;
    int32_t zero1;
    float angle;
    float major_axis;
    float minor_axis;
    GLDMTVector millimeters;
    int32_t zero2[2];
    float unknown;
} GLDMTTouch;

typedef struct {
    int32_t identifier;
    int32_t state;
    float x;
    float y;
    float vx;
    float vy;
    float size;
} GLDTouchPoint;

typedef void (*GLDTFrameCallback)(
    const GLDTouchPoint *points,
    int32_t count,
    double timestamp,
    void *context
);

typedef int32_t GLDTStatus;
enum {
    GLDTStatusAvailable = 0,
    GLDTStatusInvalidCallback = 1,
    GLDTStatusFrameworkUnavailable = 2,
    GLDTStatusRequiredSymbolsUnavailable = 3,
    GLDTStatusDefaultDeviceUnavailable = 4,
    GLDTStatusStartFailed = 5
};

GLDTStatus GLDTGetAvailabilityStatus(void);
GLDTStatus GLDTGetLastStartStatus(void);
bool GLDTIsAvailable(void);

// Whether the device Glide holds is still started. A sleep/wake cycle can leave the
// handle in place while the hardware behind it has gone, and a handle acquired
// before the trackpad finishes re-enumerating never delivers a frame; either way
// this reports false and the device needs rebuilding. False also when nothing is
// started. True when the state cannot be established, so a working device is never
// torn down on a guess.
bool GLDTIsDeviceRunning(void);
bool GLDTStart(GLDTFrameCallback callback, void *context);
void GLDTStop(void);

/// Fewest simultaneous contacts a frame must carry to be forwarded to Swift.
/// Defaults to 3 — the floor for every gesture rule — which keeps one- and
/// two-finger cursor work entirely out of the app. Features that need sparser
/// contact (the corner TrackPoint reads a single finger) lower it to 1 while
/// they are enabled. Clamped to 1...32; safe to call from any thread.
void GLDTSetMinimumContactCount(int32_t count);

/// Physical size of the sensor surface in millimetres, or false when the device or
/// the symbol is unavailable.
///
/// Edge margins are configured in millimetres so the same number feels the same on
/// any trackpad. Assuming a nominal size instead makes that a lie on every machine
/// whose trackpad differs — the setting silently means something else.
bool GLDTGetSurfaceDimensions(double *width_mm, double *height_mm);

#endif
