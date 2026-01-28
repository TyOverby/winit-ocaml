# Implement Synchronous Error Scope Support

## Background

WebGPU provides error scopes for explicit error handling via `push_error_scope` and `pop_error_scope`. While the WebGPU headers spec defines `pop_error_scope` as an async callback-based API, **wgpu-native calls callbacks synchronously** before the function returns.

This is consistent with how wgpu-native handles other "async" operations:
- `wgpuInstanceWaitAny` is unimplemented (panics)
- `timedWaitAnyEnable` capability is always `false`
- All callbacks are invoked inline before the async function returns

The existing sync shims for `request_adapter`, `request_device`, and `buffer_map` already exploit this behavior.

## Current State

- `Device.push_error_scope` - Already implemented
- `Device.pop_error_scope` - Marked as TODO in `wgpu_low.ml:8216`
- Related enums exist: `Error_filter.t`, `Error_type.t`, `Pop_error_scope_status.t`

## Implementation Plan

### 1. Add C Stub in `codegen/templates/low/sync_helpers.c`

```c
/* Error scope result capture structure */
struct ErrorScopeResult {
  WGPUPopErrorScopeStatus status;
  WGPUErrorType error_type;
  char message[1024];  /* Copy message since WGPUStringView is temporary */
};

static void handle_pop_error_scope_sync(WGPUPopErrorScopeStatus status,
                                        WGPUErrorType type,
                                        WGPUStringView message,
                                        void *userdata1, void *userdata2) {
  (void)userdata2;
  struct ErrorScopeResult *result = (struct ErrorScopeResult *)userdata1;
  result->status = status;
  result->error_type = type;
  if (message.data && message.length > 0) {
    size_t len = message.length < 1023 ? message.length : 1023;
    memcpy(result->message, message.data, len);
    result->message[len] = '\0';
  } else {
    result->message[0] = '\0';
  }
}

CAMLprim value caml_wgpu_device_pop_error_scope_sync(value device_val) {
  CAMLparam1(device_val);
  CAMLlocal1(result_tuple);

  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);

  struct ErrorScopeResult result = {0};

  WGPUPopErrorScopeCallbackInfo callback_info = {
    .callback = handle_pop_error_scope_sync,
    .userdata1 = &result,
    .userdata2 = NULL,
  };

  wgpuDevicePopErrorScope(device, callback_info);

  /* Return as tuple: (status, error_type, message) */
  result_tuple = caml_alloc_tuple(3);
  Store_field(result_tuple, 0, Val_int(result.status));
  Store_field(result_tuple, 1, Val_int(result.error_type));
  Store_field(result_tuple, 2, caml_copy_string(result.message));

  CAMLreturn(result_tuple);
}
```

### 2. Add Low-Level Binding in `codegen/templates/low/convenience_functions.ml`

```ocaml
external device_pop_error_scope_sync
  :  device
  -> int * int * string
  = "caml_wgpu_device_pop_error_scope_sync"
```

### 3. Add High-Level Wrapper in `codegen/templates/high/device.ml`

```ocaml
module Error_scope_result = struct
  type t =
    { status : Pop_error_scope_status.t
    ; error_type : Error_type.t
    ; message : string
    }
end

let pop_error_scope t =
  let status_int, error_type_int, message =
    Wgpu_low.device_pop_error_scope_sync t.handle
  in
  { Error_scope_result.
    status = Pop_error_scope_status.of_int status_int
  ; error_type = Error_type.of_int error_type_int
  ; message
  }
```

### 4. Expose in `codegen/templates/high/device.mli`

```ocaml
module Error_scope_result : sig
  type t =
    { status : Pop_error_scope_status.t
    ; error_type : Error_type.t
    ; message : string
    }
end

val pop_error_scope : t -> Error_scope_result.t
```

## Testing

Create a test file `test/test_error_scopes.ml` that demonstrates error capture:

### Test 1: No Error Case

```ocaml
let test_no_error () =
  let instance = Instance.create () in
  let adapter = Instance.request_adapter instance () in
  let device = Adapter.request_device adapter in

  (* Push a validation error scope *)
  Device.push_error_scope device ~filter:Error_filter.Validation;

  (* Do something that succeeds - create a valid buffer *)
  let _buffer = Device.create_buffer device
    ~label:"valid_buffer"
    ~size:64L
    ~usage:Buffer_usage.(singleton Copy_dst)
    ~mapped_at_creation:false
  in

  (* Pop should show no error *)
  let result = Device.pop_error_scope device in
  assert (result.error_type = Error_type.No_error);
  assert (result.message = "");
  print_endline "test_no_error: PASSED"
```

### Test 2: Validation Error Case

```ocaml
let test_validation_error () =
  let instance = Instance.create () in
  let adapter = Instance.request_adapter instance () in
  let device = Adapter.request_device adapter in

  (* Push a validation error scope *)
  Device.push_error_scope device ~filter:Error_filter.Validation;

  (* Do something that triggers a validation error *)
  (* For example: create a buffer with size 0, or invalid usage flags *)
  let _buffer = Device.create_buffer device
    ~label:"invalid_buffer"
    ~size:0L  (* Size 0 may trigger validation error *)
    ~usage:Buffer_usage.empty  (* No usage flags - invalid *)
    ~mapped_at_creation:false
  in

  (* Pop should capture the validation error *)
  let result = Device.pop_error_scope device in
  assert (result.error_type = Error_type.Validation);
  assert (String.length result.message > 0);
  Printf.printf "test_validation_error: PASSED (message: %s)\n" result.message
```

### Test 3: Nested Error Scopes

```ocaml
let test_nested_scopes () =
  let instance = Instance.create () in
  let adapter = Instance.request_adapter instance () in
  let device = Adapter.request_device adapter in

  (* Push outer scope for OOM errors *)
  Device.push_error_scope device ~filter:Error_filter.Out_of_memory;

  (* Push inner scope for validation errors *)
  Device.push_error_scope device ~filter:Error_filter.Validation;

  (* Trigger a validation error *)
  let _buffer = Device.create_buffer device
    ~label:"bad"
    ~size:0L
    ~usage:Buffer_usage.empty
    ~mapped_at_creation:false
  in

  (* Pop inner scope - should have validation error *)
  let inner_result = Device.pop_error_scope device in
  assert (inner_result.error_type = Error_type.Validation);

  (* Pop outer scope - should have no error (validation was caught by inner) *)
  let outer_result = Device.pop_error_scope device in
  assert (outer_result.error_type = Error_type.No_error);

  print_endline "test_nested_scopes: PASSED"
```

### Test 4: Error Not Matching Filter

```ocaml
let test_filter_mismatch () =
  let instance = Instance.create () in
  let adapter = Instance.request_adapter instance () in
  let device = Adapter.request_device adapter in

  (* Push scope for OOM errors only *)
  Device.push_error_scope device ~filter:Error_filter.Out_of_memory;

  (* Trigger a validation error (not OOM) *)
  let _buffer = Device.create_buffer device
    ~label:"bad"
    ~size:0L
    ~usage:Buffer_usage.empty
    ~mapped_at_creation:false
  in

  (* Pop scope - validation error should NOT be captured by OOM filter *)
  (* The error goes to uncaptured error handler instead *)
  let result = Device.pop_error_scope device in
  assert (result.error_type = Error_type.No_error);

  print_endline "test_filter_mismatch: PASSED"
```

### Finding a Reliable Validation Error Trigger

Some operations that reliably trigger validation errors:
1. Buffer with `size: 0L` and `usage: Buffer_usage.empty`
2. Creating a bind group with mismatched layout
3. Creating a shader module with invalid WGSL
4. Calling `create_render_pipeline` with invalid configuration

Test which of these reliably triggers a validation error in the test environment.

## Validation Criteria

1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. `dune exec test/test_error_scopes.exe` passes all tests
4. Error messages are non-empty when errors occur
5. Nested scopes work correctly (inner scope catches error, outer sees nothing)

## Notes

- The sync shim pattern relies on wgpu-native calling callbacks synchronously. This is an implementation detail, not a spec guarantee.
- The error message is copied into a fixed-size buffer because `WGPUStringView` points to temporary memory that may be freed after the callback returns.
- The `Pop_error_scope_status` enum has values like `Success`, `Instance_dropped`, `Empty_stack` - check for these in robust error handling.
