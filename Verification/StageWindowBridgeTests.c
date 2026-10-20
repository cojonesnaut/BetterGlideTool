// Exercise production bridge sequencing with fake callbacks. Never posts input
// to a real process, changes focus or queries the user's windows.
#include <assert.h>
#include <stdio.h>
#include "../Sources/Actions/Components/GlideWindowServerBridge.c"
static uint32_t requested_id, requested_mode;
static int events, front_result, pid_result;
static int32_t process_stub(pid_t pid, GLDWProcessSerialNumber *psn) {
    assert(pid == 42); psn->low = 42; return pid_result;
}
static CGError front_stub(GLDWProcessSerialNumber *psn, uint32_t window, uint32_t mode) {
    assert(psn->low == 42); requested_id = window; requested_mode = mode; return front_result;
}
static CGError event_stub(GLDWProcessSerialNumber *psn, uint8_t *bytes) {
    assert(psn->low == 42);
    uint32_t id; memcpy(&id, bytes + 0x3c, sizeof(id)); assert(id == 123);
    assert(bytes[0x08] == (events == 0 ? kCGEventLeftMouseDown : kCGEventLeftMouseUp));
    CGPoint point; memcpy(&point, bytes + 0x20, sizeof(point));
    assert(point.x == -1 && point.y == -1);
    events++; return kCGErrorSuccess;
}
static int connection_stub(void) { return 1; }
static CFStringRef display_stub(int connection, uint32_t window) {
    assert(connection == 1 && window == 123);
    return CFRetain(CFSTR("00000000-0000-0000-0000-000000000001"));
}
static uint32_t display_id_stub(CFUUIDRef uuid) { assert(uuid); return 7; }
int main(void) {
    pthread_once(&bridge_init_once, init_bridge_symbols);
    // Replace every callback exercised below before calling the bridge.
    fn_get_process = process_stub; fn_set_front = front_stub; fn_post_event = event_stub;
    fn_main_connection = connection_stub; fn_display_for_window = display_stub;
    fn_display_from_uuid = display_id_stub;
    assert(!GLDWFocusWindow(0, 123) && !GLDWFocusWindow(42, 0));
    assert(GLDWFocusWindow(42, 123));
    assert(requested_id == 123 && requested_mode == 0x200 && events == 2);
    events = 0; front_result = kCGErrorFailure;
    assert(!GLDWFocusWindow(42, 123) && events == 0);
    front_result = 0; pid_result = -1;
    assert(!GLDWFocusWindow(42, 123) && events == 0);
    pid_result = 0; fn_post_event = NULL;
    assert(!GLDWFocusWindow(42, 123) && events == 0);
    assert(GLDWDisplayForWindow(123) == 7 && GLDWDisplayForWindow(0) == 0);
    fn_display_from_uuid = NULL;
    assert(GLDWDisplayForWindow(123) == 0);
    puts("PASS: exact-window focus ID/mode/event pairing, rejected requests and display lookup compatibility guards");
}
