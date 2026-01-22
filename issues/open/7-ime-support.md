# Add IME (Input Method Editor) Support

## Background

IME events allow handling text composition for complex input methods (e.g., Chinese, Japanese, Korean input, accented characters). This is essential for international text input.

## What's Missing

winit provides `WindowEvent::Ime` with three variants:
- `Ime::Enabled` - IME was enabled
- `Ime::Preedit(String, Option<(usize, usize)>)` - Composition text and cursor range
- `Ime::Commit(String)` - Final committed text

## Implementation Challenges

1. **String Handling in FFI**: Need to marshal Rust strings across C FFI boundary
2. **Optional Data**: Cursor range is optional, requires null handling
3. **Unicode Safety**: Must preserve UTF-8 encoding through FFI layers

## Proposed Approach

### Option A: Fixed-size buffer
- Use fixed char array (e.g., 256 bytes) for preedit/commit text
- Simple FFI, but limited text length
- Truncate if text exceeds buffer

### Option B: Dynamic allocation
- Allocate OCaml strings from C stubs
- More complex, but supports arbitrary length
- Better matches winit's API

### Option C: Callback-based
- Register OCaml callback for IME events
- Call from Rust when IME events occur
- Most flexible, but complex lifetime management

## Recommended: Option B

Use OCaml string allocation in C stubs for maximum flexibility:

```c
CAMLprim value caml_winit_ime_commit(value app_val) {
    // Get IME commit text from Rust (via new FFI function)
    const char* text = winit_get_ime_text(app);
    value ocaml_str = caml_copy_string(text);
    winit_free_ime_text(text);  // Free Rust-allocated string
    return ocaml_str;
}
```

## OCaml API

```ocaml
type ime_event =
  | Enabled
  | Preedit of { text: string; cursor: (int * int) option }
  | Commit of string

type event =
  | (* existing events *)
  | Ime of ime_event
```

## Notes

- Must call `window.set_ime_allowed(true)` to enable IME
- Platform support: **macOS, Windows, X11, Wayland** ✓; **iOS, Android, Web** ✗
- Consider adding IME position control for floating composition window

## References

- [winit IME docs](https://docs.rs/winit/latest/winit/event/enum.Ime.html)
- [OCaml string handling](https://ocaml.org/manual/intfc.html#ss:c-simple-io)
