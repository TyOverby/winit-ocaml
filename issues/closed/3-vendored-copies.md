# Vendored copies

Right now, we have `winit` and `softbuffer` vendored.  It's hard to commit
changes here because they're set up to point at the upstream source on github. 

Using the `gh` tool, create forks of these projects on my account (TyOverby)
and change the remotes of these vendored so that the git submodules can point
to the forks.

Then edit `CLAUDE.md` so that it contains instructions on what to do if you
need to made changes to any of the vendored code.

## Currently

The project currently has two vendored dependencies as git submodules:

1. **winit** at `rust/vendor/winit`
   - URL: git@github.com:rust-windowing/winit.git
   - Points to upstream rust-windowing/winit
   - Remote named "origin"

2. **softbuffer** at `rust/vendor/softbuffer`
   - URL: git@github.com:rust-windowing/softbuffer.git
   - Points to upstream rust-windowing/softbuffer
   - Remote named "origin"

Both submodules are configured in `.gitmodules` and point to the upstream repositories.
This makes it difficult to commit changes since we don't have write access to the
upstream repositories.

## Addressing

I've successfully addressed this issue by:

1. **Created GitHub forks** of both upstream repositories:
   - Used `gh repo fork rust-windowing/winit --clone=false` to fork winit
   - Used `gh repo fork rust-windowing/softbuffer --clone=false` to fork softbuffer
   - Both forks are now available under the TyOverby GitHub account

2. **Updated submodule remotes**:
   - Changed winit submodule remote from rust-windowing/winit to TyOverby/winit
   - Changed softbuffer submodule remote from rust-windowing/softbuffer to TyOverby/softbuffer
   - Updated `.gitmodules` file to reflect the new fork URLs

3. **Added comprehensive documentation** to `CLAUDE.md`:
   - Created new "Working with vendored dependencies" section
   - Documented why dependencies are vendored
   - Explained the submodule configuration pointing to TyOverby forks
   - Provided step-by-step instructions for making changes to vendored code
   - Included workflow for syncing with upstream repositories

The vendored dependencies now point to forks that we have write access to, making it
possible to commit and push changes when needed. The documentation ensures future
maintainers know how to work with these vendored dependencies.

