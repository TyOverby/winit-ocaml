#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/bigarray.h>
#include <caml/fail.h>
#include <string.h>
#include <stdlib.h>

// Forward declarations of Rust FFI functions
extern void* softbuffer_surface_create(const void* window_handle);
extern int softbuffer_surface_resize(void* surface, unsigned int width, unsigned int height);
extern unsigned int* softbuffer_surface_get_buffer(void* surface, unsigned int* width_out, unsigned int* height_out);
extern int softbuffer_surface_get_buffer_age(const void* surface);
extern int softbuffer_surface_present(void* surface);
extern int softbuffer_surface_present_with_damage(void* surface, const void* damage_rects, size_t damage_count);
extern void softbuffer_surface_destroy(void* surface);

// Damage rectangle (must match Rust)
typedef struct {
    unsigned int x;
    unsigned int y;
    unsigned int width;
    unsigned int height;
} DamageRect;

// Custom block for surface handle
static void softbuffer_surface_finalize(value v) {
    void* surface = *((void**)Data_custom_val(v));
    if (surface != NULL) {
        softbuffer_surface_destroy(surface);
    }
}

static struct custom_operations softbuffer_surface_ops = {
    "softbuffer_surface",
    softbuffer_surface_finalize,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default
};

// Wrap surface pointer in OCaml custom block
static value alloc_softbuffer_surface(void* surface) {
    value v = caml_alloc_custom(&softbuffer_surface_ops, sizeof(void*), 0, 1);
    *((void**)Data_custom_val(v)) = surface;
    return v;
}

// Extract surface pointer from OCaml value
static void* softbuffer_surface_val(value v) {
    return *((void**)Data_custom_val(v));
}

// Extract window handle pointer from OCaml value
static const void* winit_window_handle_val(value v) {
    return *((const void**)Data_custom_val(v));
}

// OCaml: external create : Winit.window_handle -> surface = "caml_softbuffer_surface_create"
CAMLprim value caml_softbuffer_surface_create(value handle_val) {
    CAMLparam1(handle_val);
    CAMLlocal1(result);

    const void* handle = winit_window_handle_val(handle_val);
    void* surface = softbuffer_surface_create(handle);

    if (surface == NULL) {
        caml_failwith("Failed to create softbuffer surface");
    }

    result = alloc_softbuffer_surface(surface);
    CAMLreturn(result);
}

// OCaml: external resize : surface -> width:int -> height:int -> unit = "caml_softbuffer_surface_resize"
CAMLprim value caml_softbuffer_surface_resize(value surface_val, value width_val, value height_val) {
    CAMLparam3(surface_val, width_val, height_val);

    void* surface = softbuffer_surface_val(surface_val);
    unsigned int width = Int_val(width_val);
    unsigned int height = Int_val(height_val);

    int result = softbuffer_surface_resize(surface, width, height);
    if (result < 0) {
        caml_failwith("softbuffer_surface_resize failed");
    }

    CAMLreturn(Val_unit);
}

// OCaml: external get_buffer : surface -> (int * int * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t) = "caml_softbuffer_surface_get_buffer"
CAMLprim value caml_softbuffer_surface_get_buffer(value surface_val) {
    CAMLparam1(surface_val);
    CAMLlocal2(result, ba);

    void* surface = softbuffer_surface_val(surface_val);

    unsigned int width, height;
    unsigned int* buffer = softbuffer_surface_get_buffer(surface, &width, &height);

    if (buffer == NULL) {
        caml_failwith("softbuffer_surface_get_buffer failed");
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

// OCaml: external get_buffer_age : surface -> int = "caml_softbuffer_surface_get_buffer_age"
CAMLprim value caml_softbuffer_surface_get_buffer_age(value surface_val) {
    CAMLparam1(surface_val);

    void* surface = softbuffer_surface_val(surface_val);

    int age = softbuffer_surface_get_buffer_age(surface);
    if (age < 0) {
        caml_failwith("softbuffer_surface_get_buffer_age failed");
    }

    CAMLreturn(Val_int(age));
}

// OCaml: external present : surface -> unit = "caml_softbuffer_surface_present"
CAMLprim value caml_softbuffer_surface_present(value surface_val) {
    CAMLparam1(surface_val);

    void* surface = softbuffer_surface_val(surface_val);

    int result = softbuffer_surface_present(surface);
    if (result < 0) {
        caml_failwith("softbuffer_surface_present failed");
    }

    CAMLreturn(Val_unit);
}

// OCaml: external present_with_damage_impl : surface -> (int * int * int * int) array -> unit = "caml_softbuffer_surface_present_with_damage"
CAMLprim value caml_softbuffer_surface_present_with_damage(value surface_val, value rects_val) {
    CAMLparam2(surface_val, rects_val);

    void* surface = softbuffer_surface_val(surface_val);

    // Get array size
    mlsize_t count = Wosize_val(rects_val);

    // Allocate C array for damage rects
    DamageRect* rects = NULL;
    if (count > 0) {
        rects = (DamageRect*)malloc(sizeof(DamageRect) * count);
        if (rects == NULL) {
            caml_failwith("Failed to allocate damage rects");
        }

        // Convert OCaml tuples to C structs
        for (mlsize_t i = 0; i < count; i++) {
            value rect_tuple = Field(rects_val, i);
            rects[i].x = Int_val(Field(rect_tuple, 0));
            rects[i].y = Int_val(Field(rect_tuple, 1));
            rects[i].width = Int_val(Field(rect_tuple, 2));
            rects[i].height = Int_val(Field(rect_tuple, 3));
        }
    }

    // Call Rust FFI
    int result = softbuffer_surface_present_with_damage(surface, rects, count);

    // Free allocated memory
    if (rects != NULL) {
        free(rects);
    }

    if (result < 0) {
        caml_failwith("softbuffer_surface_present_with_damage failed");
    }

    CAMLreturn(Val_unit);
}
