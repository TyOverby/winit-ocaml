# Wacom tablet support

On linux/x11, wacom tablet inputs appear to be getting dropped.  Even when I added println debugging in the rust code for 
unhandled input events, nothing was showing up on pen hover, pen move, or pen down/up.  Look through the winit codebase to 
see if there's anything that we're doing wrong.

## links
- [commit that added tablet support to winit](https://github.com/rust-windowing/winit/commit/f046e778aa0d2621fdedf03eab53e88120317192#diff-f7d292f3547150aa761570c5bd5407ebfbeece35f03c4420d4de9e8bc3bf26f9)
