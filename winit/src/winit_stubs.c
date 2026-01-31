#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <string.h>

// Forward declarations of Rust FFI functions
extern void* winit_window_create(void);
extern int winit_window_pump_events(void* window, void* events_out, size_t max_events);
extern const void* winit_window_get_handle(const void* window);
extern void winit_window_handle_release(const void* handle);
extern void winit_window_destroy(void* window);
extern int winit_test_version(void);

// Raw window handle backend types (must match Rust)
typedef enum {
    RAW_HANDLE_BACKEND_X11 = 0,
    RAW_HANDLE_BACKEND_WAYLAND = 1,
    RAW_HANDLE_BACKEND_WIN32 = 2,
    RAW_HANDLE_BACKEND_APPKIT = 3,
    RAW_HANDLE_BACKEND_UNKNOWN = 255
} RawHandleBackend;

// Raw X11 handle (must match Rust)
typedef struct {
    const void* display;
    uint64_t window;
} RawX11Handle;

// Raw Wayland handle (must match Rust)
typedef struct {
    const void* display;
    const void* surface;
} RawWaylandHandle;

// Raw Win32 handle (must match Rust)
typedef struct {
    const void* hwnd;
    const void* hinstance;
} RawWin32Handle;

// Raw AppKit handle (must match Rust)
typedef struct {
    const void* ns_view;
    const void* metal_layer;
} RawAppKitHandle;

// Union of raw handle data (must match Rust)
typedef union {
    RawX11Handle x11;
    RawWaylandHandle wayland;
    RawWin32Handle win32;
    RawAppKitHandle appkit;
} RawHandleData;

// Raw window handle info (must match Rust)
typedef struct {
    RawHandleBackend backend;
    RawHandleData data;
} RawWindowHandleInfo;

extern int winit_window_get_raw_handle(const void* window, RawWindowHandleInfo* out);

// Event type enum (must match Rust)
typedef enum {
    EVENT_NO_EVENT = 0,
    EVENT_CLOSE_REQUESTED = 1,
    EVENT_SURFACE_RESIZED = 2,
    EVENT_REDRAW_REQUESTED = 3,
    EVENT_KEY_PRESSED = 4,
    EVENT_KEY_RELEASED = 5,
    EVENT_POINTER_MOVED = 6,
    EVENT_POINTER_BUTTON_PRESSED = 7,
    EVENT_POINTER_BUTTON_RELEASED = 8,
    EVENT_POINTER_ENTERED = 9,
    EVENT_POINTER_LEFT = 10,
    EVENT_MOUSE_WHEEL = 11,
    EVENT_FOCUSED = 12,
    EVENT_UNFOCUSED = 13,
    EVENT_WINDOW_MOVED = 14,
    EVENT_MODIFIERS_CHANGED = 15,
    EVENT_DESTROYED = 16,
    EVENT_OCCLUDED = 17,
    EVENT_UNOCCLUDED = 18,
    EVENT_THEME_CHANGED = 19,
    EVENT_SCALE_FACTOR_CHANGED = 20
} EventType;

// Event structure (must match Rust)
typedef struct {
    EventType event_type;
    int data[16];
} Event;

// Custom block for window handle
static void winit_window_finalize(value v) {
    void* window = *((void**)Data_custom_val(v));
    if (window != NULL) {
        winit_window_destroy(window);
    }
}

static struct custom_operations winit_window_ops = {
    "winit_window",
    winit_window_finalize,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default
};

// Wrap window pointer in OCaml custom block
static value alloc_winit_window(void* window) {
    value v = caml_alloc_custom(&winit_window_ops, sizeof(void*), 0, 1);
    *((void**)Data_custom_val(v)) = window;
    return v;
}

// Extract window pointer from OCaml value
static void* winit_window_val(value v) {
    return *((void**)Data_custom_val(v));
}

// Custom block for window handle (non-owning reference for softbuffer)
// This does NOT have a finalizer because ownership is transferred to softbuffer
static struct custom_operations winit_window_handle_ops = {
    "winit_window_handle",
    custom_finalize_default,  // No finalizer - ownership transfers to softbuffer
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default
};

// Wrap handle pointer in OCaml custom block
static value alloc_winit_window_handle(const void* handle) {
    value v = caml_alloc_custom(&winit_window_handle_ops, sizeof(void*), 0, 1);
    *((const void**)Data_custom_val(v)) = handle;
    return v;
}

// OCaml: external create : unit -> window = "caml_winit_window_create"
CAMLprim value caml_winit_window_create(value unit) {
    CAMLparam1(unit);
    CAMLlocal1(result);

    void* window = winit_window_create();
    if (window == NULL) {
        caml_failwith("Failed to create winit window");
    }

    result = alloc_winit_window(window);
    CAMLreturn(result);
}

// OCaml: external pump_events_raw : window -> (int * int array) array = "caml_winit_window_pump_events"
CAMLprim value caml_winit_window_pump_events(value window_val) {
    CAMLparam1(window_val);
    CAMLlocal3(result, event_tuple, data_array);

    void* window = winit_window_val(window_val);

    // Allocate event buffer (max 32 events per pump)
    Event events[32];
    memset(events, 0, sizeof(events));

    int count = winit_window_pump_events(window, events, 32);

    // TODO: this isn't really a failure, it just indicates that the window was
    // closed.  This function should return a Result.t.
    if (count < 0) {
        caml_failwith("winit_window_pump_events failed");
    }

    // Convert events to OCaml array
    result = caml_alloc(count, 0);
    for (int i = 0; i < count; i++) {
        // Create tuple (event_type, data_array)
        event_tuple = caml_alloc_tuple(2);

        // Store event type
        Store_field(event_tuple, 0, Val_int(events[i].event_type));

        // Create data array
        data_array = caml_alloc(16, 0);
        for (int j = 0; j < 16; j++) {
            Store_field(data_array, j, Val_int(events[i].data[j]));
        }
        Store_field(event_tuple, 1, data_array);

        Store_field(result, i, event_tuple);
    }

    CAMLreturn(result);
}

// OCaml: external get_handle : window -> window_handle = "caml_winit_window_get_handle"
CAMLprim value caml_winit_window_get_handle(value window_val) {
    CAMLparam1(window_val);
    CAMLlocal1(result);

    void* window = winit_window_val(window_val);
    const void* handle = winit_window_get_handle(window);

    if (handle == NULL) {
        caml_failwith("Failed to get window handle");
    }

    result = alloc_winit_window_handle(handle);
    CAMLreturn(result);
}

// OCaml: external test_version : unit -> int = "caml_winit_test_version"
CAMLprim value caml_winit_test_version(value unit) {
    CAMLparam1(unit);
    int version = winit_test_version();
    CAMLreturn(Val_int(version));
}

// Forward declarations for new functions
extern int winit_window_surface_size(const void* window, uint32_t* width_out, uint32_t* height_out);
extern double winit_window_scale_factor(const void* window);

// OCaml: external surface_size : window -> int * int = "caml_winit_window_surface_size"
CAMLprim value caml_winit_window_surface_size(value window_val) {
    CAMLparam1(window_val);
    CAMLlocal1(result);

    void* window = winit_window_val(window_val);
    uint32_t width = 0, height = 0;

    int status = winit_window_surface_size(window, &width, &height);
    if (status != 0) {
        caml_failwith("Failed to get surface size");
    }

    result = caml_alloc_tuple(2);
    Store_field(result, 0, Val_int(width));
    Store_field(result, 1, Val_int(height));

    CAMLreturn(result);
}

// OCaml: external scale_factor : window -> float = "caml_winit_window_scale_factor"
CAMLprim value caml_winit_window_scale_factor(value window_val) {
    CAMLparam1(window_val);

    void* window = winit_window_val(window_val);
    double factor = winit_window_scale_factor(window);

    if (factor < 0.0) {
        caml_failwith("Failed to get scale factor");
    }

    CAMLreturn(caml_copy_double(factor));
}

// OCaml: external get_raw_handle : window -> raw_window_handle = "caml_winit_window_get_raw_handle"
// Returns a record with backend type and platform-specific data
CAMLprim value caml_winit_window_get_raw_handle(value window_val) {
    CAMLparam1(window_val);
    CAMLlocal2(result, handle_data);

    void* window = winit_window_val(window_val);
    RawWindowHandleInfo info;

    int status = winit_window_get_raw_handle(window, &info);
    if (status != 0) {
        caml_failwith("Failed to get raw window handle");
    }

    // Allocate the result record
    // OCaml type: { backend: int; x11_display: nativeint; x11_window: int64;
    //               wayland_display: nativeint; wayland_surface: nativeint;
    //               win32_hwnd: nativeint; win32_hinstance: nativeint;
    //               metal_layer: nativeint }
    result = caml_alloc(8, 0);

    // Store backend type (as int)
    Store_field(result, 0, Val_int((int)info.backend));

    // Store X11 data (fields 1-2)
    if (info.backend == RAW_HANDLE_BACKEND_X11) {
        Store_field(result, 1, caml_copy_nativeint((intptr_t)info.data.x11.display));
        Store_field(result, 2, caml_copy_int64(info.data.x11.window));
    } else {
        Store_field(result, 1, caml_copy_nativeint(0));
        Store_field(result, 2, caml_copy_int64(0));
    }

    // Store Wayland data (fields 3-4)
    if (info.backend == RAW_HANDLE_BACKEND_WAYLAND) {
        Store_field(result, 3, caml_copy_nativeint((intptr_t)info.data.wayland.display));
        Store_field(result, 4, caml_copy_nativeint((intptr_t)info.data.wayland.surface));
    } else {
        Store_field(result, 3, caml_copy_nativeint(0));
        Store_field(result, 4, caml_copy_nativeint(0));
    }

    // Store Win32 data (fields 5-6)
    if (info.backend == RAW_HANDLE_BACKEND_WIN32) {
        Store_field(result, 5, caml_copy_nativeint((intptr_t)info.data.win32.hwnd));
        Store_field(result, 6, caml_copy_nativeint((intptr_t)info.data.win32.hinstance));
    } else {
        Store_field(result, 5, caml_copy_nativeint(0));
        Store_field(result, 6, caml_copy_nativeint(0));
    }

    // Store AppKit/Metal data (field 7)
    if (info.backend == RAW_HANDLE_BACKEND_APPKIT) {
        Store_field(result, 7, caml_copy_nativeint((intptr_t)info.data.appkit.metal_layer));
    } else {
        Store_field(result, 7, caml_copy_nativeint(0));
    }

    CAMLreturn(result);
}
