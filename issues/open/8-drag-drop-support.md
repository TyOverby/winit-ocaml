# Add Drag & Drop Support

## Background

Drag & drop events allow users to drag files from the file explorer onto the window. This is essential for file-based applications (image viewers, text editors, etc.).

## What's Missing

winit provides four drag & drop related events:
- `DragEntered { paths: Vec<PathBuf>, position: PhysicalPosition<f64> }` - Drag entered window
- `DragMoved { position: PhysicalPosition<f64> }` - Drag moved within window
- `DragDropped { paths: Vec<PathBuf>, position: PhysicalPosition<f64> }` - Files dropped
- `DragLeft { position: Option<PhysicalPosition<f64>> }` - Drag left window

## Implementation Challenges

1. **Path Lists**: Need to marshal `Vec<PathBuf>` across FFI
2. **Variable Length**: Number of files is dynamic
3. **Path Encoding**: Must handle platform-specific path formats (UTF-8, UTF-16, etc.)

## Proposed Approach

### Option A: Multiple FFI calls
- First call returns file count
- Subsequent calls retrieve individual paths
- Simple but requires N+1 FFI calls

### Option B: Concatenated string
- Join paths with null separator
- Single FFI call
- OCaml splits the string
- Risk of ambiguity if paths contain nulls

### Option C: OCaml list allocation
- C stubs allocate OCaml list directly
- Single FFI call, clean API
- Most complex implementation

## Recommended: Option C

Use OCaml list allocation for clean API:

```c
CAMLprim value caml_winit_get_drag_paths(value app_val) {
    CAMLparam1(app_val);
    CAMLlocal2(result, cons);

    void* app = winit_app_val(app_val);

    // Get path count and array
    size_t count;
    char** paths = winit_get_drag_paths(app, &count);

    // Build OCaml list in reverse
    result = Val_emptylist;
    for (int i = count - 1; i >= 0; i--) {
        cons = caml_alloc(2, 0);  // Cons cell
        Store_field(cons, 0, caml_copy_string(paths[i]));
        Store_field(cons, 1, result);
        result = cons;
    }

    winit_free_drag_paths(paths, count);
    CAMLreturn(result);
}
```

## OCaml API

```ocaml
type event =
  | (* existing events *)
  | DragEntered of { paths: string list; x: float; y: float }
  | DragMoved of { x: float; y: float }
  | DragDropped of { paths: string list; x: float; y: float }
  | DragLeft of { x: float; y: float }  (* position may be (0, 0) on some platforms *)
```

## Usage Example

```ocaml
| DragDropped { paths; x; y } ->
    Printf.printf "Dropped %d files at (%.1f, %.1f):\n" (List.length paths) x y;
    List.iter (fun path -> Printf.printf "  - %s\n" path) paths;
    open_files paths
```

## Platform Support

- **Windows**: Full support ✓
- **macOS**: Full support ✓
- **Linux (X11/Wayland)**: Full support ✓
- **iOS/Android/Web**: Limited or no support ✗

## Notes

- Some platforms may limit the number of files that can be dragged
- Paths should be validated before use (existence, permissions, etc.)
- Consider security implications of processing user-provided paths
- `DragLeft.position` is always `None` on Windows

## References

- [winit drag & drop docs](https://docs.rs/winit/latest/winit/event/enum.WindowEvent.html#variant.DroppedFile)
- [OCaml list manipulation](https://ocaml.org/manual/intfc.html#ss:c-from-ocaml)
