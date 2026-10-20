// Run the real filtering callback with synthetic contacts, without opening hardware.
#include "../Sources/Gestures/Components/GlideMultitouchBridge.c"
#include <assert.h>
#include <stdio.h>

static int delivered = 0;
static bool first_record = true;
static bool write_frames = true;
static void record_frame(const GLDTouchPoint *points, int32_t count, double time, void *context) {
    (void)context;
    delivered++;
    if (!write_frames) return;
    printf("%s{\"time\":%.4f,\"contacts\":[", first_record ? "" : ",", time);
    first_record = false;
    for (int i = 0; i < count; i++) {
        printf("%s{\"id\":%d,\"x\":%.4f,\"y\":%.4f,\"size\":%.4f}", i ? "," : "",
               points[i].identifier, points[i].x, points[i].y, points[i].size);
    }
    printf("]}");
}
int main(void) {
    client_callback = record_frame;
    minimum_contact_count = 1;
    GLDTSetContactDetailsEnabled(true);
    printf("[");
    for (int anchors = 1; anchors <= 3; anchors++) {
        for (int side = 0; side < (anchors == 2 ? 3 : 2); side++) {
            forwarding_gesture = false; last_forwarded_active_count = 0;
            first_record = true;
            printf("%s{\"anchors\":%d,\"side\":%d,\"frames\":[", anchors == 1 && side == 0 ? "" : ",", anchors, side);
            MTTouch touches[4] = {0};
            for (int i = 0; i < anchors; i++) {
                touches[i].identifier = i + 1; touches[i].state = 4;
                touches[i].normalized.position.x = 0.4f + i * 0.1f;
                touches[i].normalized.position.y = 0.5f; touches[i].size = 0.8f;
            }
            contact_frame_callback(NULL, touches, anchors, 10, 0);
            int start_count = delivered;
            // Stationary resting fingers must not look like lost delivery.
            for (int sample = 1; sample <= 8; sample++) contact_frame_callback(NULL, touches, anchors, 10 + sample * 0.25, 0);
            assert(delivered > start_count && "Stationary anchor frames must be forwarded");
            touches[anchors].identifier = 20; touches[anchors].state = 4;
            touches[anchors].normalized.position.x = side == 0 ? 0.2f : (anchors == 2 && side == 1 ? 0.45f : 0.8f);
            touches[anchors].normalized.position.y = 0.5f; touches[anchors].size = 0.1f;
            contact_frame_callback(NULL, touches, anchors + 1, 12.1, 0);
            start_count = delivered;
            touches[anchors].size = 0.8f;
            contact_frame_callback(NULL, touches, anchors + 1, 12.15, 0);
            assert(delivered == start_count + 1 && "Contact-size growth must reach TipTap recognition");
            contact_frame_callback(NULL, touches, anchors, 12.22, 0);
            // Keep the same anchors down for repeated taps; never require a
            // whole-hand lift to rearm, even after another long stationary rest.
            for (int sample = 1; sample <= 8; sample++) contact_frame_callback(NULL, touches, anchors, 12.22 + sample * 0.25, 0);
            touches[anchors].size = 0.1f;
            contact_frame_callback(NULL, touches, anchors + 1, 14.4, 0);
            touches[anchors].size = 0.8f;
            contact_frame_callback(NULL, touches, anchors + 1, 14.45, 0);
            contact_frame_callback(NULL, touches, anchors, 14.52, 0);
            contact_frame_callback(NULL, NULL, 0, 14.7, 0);
            printf("]}");
        }
    }
    printf("]\n");
    write_frames = false;
    int before = delivered;
    for (int i = 0; i < 100; i++) contact_frame_callback(NULL, NULL, 0, 20 + i * 0.01, 0);
    assert(delivered == before && "Idle input never emits heartbeats");
    MTTouch contacts[3] = {0};
    for (int i = 0; i < 3; i++) {
        contacts[i].identifier = i; contacts[i].state = 4;
        contacts[i].normalized.position.x = 0.3f + i * 0.1f;
        contacts[i].normalized.position.y = 0.5f; contacts[i].size = 0.2f;
    }
    contact_frame_callback(NULL, contacts, 3, 30, 0);
    before = delivered;
    contacts[2].size = 0.8f;
    contact_frame_callback(NULL, contacts, 3, 30.001, 0);
    assert(delivered == before && "Detail changes retain frame rate limits");
    contact_frame_callback(NULL, contacts, 3, 30.02, 0);
    assert(delivered == before + 1 && "Growth reaches the next eligible frame");
    before = delivered;
    for (int i = 1; i <= 20; i++) contact_frame_callback(NULL, contacts, 3, 30.02 + i * 0.01, 0);
    assert(delivered == before && "Stationary input does not flood callbacks");
    GLDTSetContactDetailsEnabled(false);
    contacts[2].size = 0.3f;
    contact_frame_callback(NULL, contacts, 3, 31, 0);
    assert(delivered == before && "Legacy movement-only gating is unchanged when disabled");
    contacts[0].normalized.position.x += 0.05f;
    contact_frame_callback(NULL, contacts, 3, 31.02, 0);
    assert(delivered == before + 1 && "Legacy movement still forwards");
    contact_frame_callback(NULL, NULL, 0, 31.021, 0);
    assert(delivered == before + 2 && "Final release bypasses frame rate limiting");
    fprintf(stderr, "PASS: real trackpad bridge stationary/contact-size fixtures for seven TipTaps\n");
    return 0;
}
