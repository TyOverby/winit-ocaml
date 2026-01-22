#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/bigarray.h>
#include <caml/fail.h>
#include <string.h>

// Forward declarations of Rust FFI functions
extern void* winit_create(void);
extern int winit_pump_events(void* app, void* events_out, size_t max_events);
extern unsigned int* winit_get_buffer(void* app, unsigned int* width_out, unsigned int* height_out);
extern int winit_present(void* app);
extern void winit_destroy(void* app);
extern int winit_test_version(void);

// Event type enum (must match Rust)
typedef enum {
    EVENT_NO_EVENT = 0,
    EVENT_CLOSE_REQUESTED = 1,
    EVENT_RESIZED = 2,
    EVENT_REDRAW_REQUESTED = 3,
    EVENT_KEY_PRESSED = 4,
    EVENT_KEY_RELEASED = 5,
    EVENT_MOUSE_MOVED = 6,
    EVENT_MOUSE_BUTTON_PRESSED = 7,
    EVENT_MOUSE_BUTTON_RELEASED = 8
} EventType;

// Event structure (must match Rust)
typedef struct {
    EventType event_type;
    int data1;
    int data2;
} Event;

// Custom block for app handle
static void winit_app_finalize(value v) {
    void* app = (void*)Field(v, 1);
    if (app != NULL) {
        winit_destroy(app);
    }
}

static struct custom_operations winit_app_ops = {
    "winit_app",
    winit_app_finalize,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default
};

// Wrap app pointer in OCaml custom block
static value alloc_winit_app(void* app) {
    value v = caml_alloc_custom(&winit_app_ops, sizeof(void*), 0, 1);
    *((void**)Data_custom_val(v)) = app;
    return v;
}

// Extract app pointer from OCaml value
static void* winit_app_val(value v) {
    return *((void**)Data_custom_val(v));
}

// OCaml: external winit_create : unit -> app = "caml_winit_create"
CAMLprim value caml_winit_create(value unit) {
    CAMLparam1(unit);
    CAMLlocal1(result);

    void* app = winit_create();
    if (app == NULL) {
        caml_failwith("Failed to create winit app");
    }

    result = alloc_winit_app(app);
    CAMLreturn(result);
}

// OCaml: external winit_pump_events : app -> event array = "caml_winit_pump_events"
CAMLprim value caml_winit_pump_events(value app_val) {
    CAMLparam1(app_val);
    CAMLlocal1(result);

    void* app = winit_app_val(app_val);

    // Allocate event buffer (max 32 events per pump)
    Event events[32];
    memset(events, 0, sizeof(events));

    int count = winit_pump_events(app, events, 32);

    if (count < 0) {
        caml_failwith("winit_pump_events failed");
    }

    // Convert events to OCaml array
    result = caml_alloc(count, 0);
    for (int i = 0; i < count; i++) {
        value event_tuple = caml_alloc_tuple(3);
        Store_field(event_tuple, 0, Val_int(events[i].event_type));
        Store_field(event_tuple, 1, Val_int(events[i].data1));
        Store_field(event_tuple, 2, Val_int(events[i].data2));
        Store_field(result, i, event_tuple);
    }

    CAMLreturn(result);
}

// OCaml: external winit_get_buffer : app -> (int * int * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t) = "caml_winit_get_buffer"
CAMLprim value caml_winit_get_buffer(value app_val) {
    CAMLparam1(app_val);
    CAMLlocal2(result, ba);

    void* app = winit_app_val(app_val);

    unsigned int width, height;
    unsigned int* buffer = winit_get_buffer(app, &width, &height);

    if (buffer == NULL) {
        caml_failwith("winit_get_buffer failed");
    }

    // Create bigarray that wraps the buffer
    intnat dims[1];
    dims[0] = (intnat)(width * height);
    ba = caml_ba_alloc(CAML_BA_INT32 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL, 1, buffer, dims);

    // Return tuple (width, height, buffer)
    result = caml_alloc_tuple(3);
    Store_field(result, 0, Val_int(width));
    Store_field(result, 1, Val_int(height));
    Store_field(result, 2, ba);

    CAMLreturn(result);
}

// OCaml: external winit_present : app -> unit = "caml_winit_present"
CAMLprim value caml_winit_present(value app_val) {
    CAMLparam1(app_val);

    void* app = winit_app_val(app_val);

    int result = winit_present(app);
    if (result < 0) {
        caml_failwith("winit_present failed");
    }

    CAMLreturn(Val_unit);
}

// OCaml: external winit_test_version : unit -> int = "caml_winit_test_version"
CAMLprim value caml_winit_test_version(value unit) {
    CAMLparam1(unit);
    int version = winit_test_version();
    CAMLreturn(Val_int(version));
}
