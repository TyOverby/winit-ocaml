@readme.md
@developer.md

# Issue tracking and management

Tasks and issues are tracked in the `./issues` directory, which contain subdirectories 
`./issues/open` and `./issues/closed`.  Markdown files in these directories are used to 
track the status of issues.

Claude is encouraged to create new issues in `./issues/open` to be worked on in the future.

## Issue workflow

1. You'll be directed to work on an issue in `./issues/open`
2. Read that issue carefully.
3. Explore the repository and take notes on the current status of the repository in a new `## Currently` section in the isse markdown file (the project may have changed since the issue was filed!) 
4. Dig into the code more deeply and use the internet to do any necessary research. Add a new `## Notes` section to the issue with information that you've learned.
5. Begin working on addressing the issue.  As you go, feel free to add notes to the issue file under a new `## Addressing` header
   that talks about how you're going about addressing the issue.
6. Ensure that the project builds (`./build.sh`), doesn't contain any warnings and that tests pass
7. After making all the changes that you see fit, ensure that the `## Addressing` section is accurate
8. *IMPORTANT*: Ensure that all documentation (e.g. `./developer.md`) is up to date
9. Use `git mv` to move the issue file into `./issues/closed`
10. Run code formatters (`./fmt.sh`)
11. Commit your changes, and create a new pull request using the `gh` tool.
12. Move back to the `master` branch
13. File any new issues that you came across in `./issues/open` for future work.
14. Commit the new issues directoy to `master` and push
15. Ensure that `git status` is totally clean (if necessary, run `git submodule update` to revert submodule changes)

## Merging pull requests

If a pull request is to be merged,

1. Switch to the appropriate branch
2. Merge `master` into it
3. Fix any merge conflicts
4. Ensure that the repo builds, and tests behave as expected

# Project ownership
You (Claude) are the owner of this project.  You should feel responsible to make decisions and exercise your ownership
to further the project.

# Working with vendored dependencies

The project vendors two Rust dependencies as git submodules in `rust/vendor/`:

- **winit**: Window creation and event handling library
- **softbuffer**: Software rendering to window surfaces

## Why vendored?

These dependencies are vendored to allow us to:
1. Make custom modifications when needed
2. Explore the source code easily during development
3. Ensure reproducible builds with specific versions

## Submodule configuration

Both submodules point to **forks** under the TyOverby GitHub account:
- `rust/vendor/winit` → git@github.com:TyOverby/winit.git
- `rust/vendor/softbuffer` → git@github.com:TyOverby/softbuffer.git

These forks allow us to commit and push changes without needing upstream maintainer approval.

## Making changes to vendored code

If you need to modify code in a vendored dependency:

1. **Navigate to the submodule directory**:
   ```bash
   cd rust/vendor/winit  # or rust/vendor/softbuffer
   ```

2. **Create a new branch** for your changes:
   ```bash
   git checkout -b my-feature-branch
   ```

3. **Make your changes** to the vendored code as needed.

4. **Commit your changes** within the submodule:
   ```bash
   git add .
   git commit -m "Description of changes"
   ```

5. **Push to the fork**:
   ```bash
   git push origin my-feature-branch
   ```

6. **Update the parent repository** to reference the new commit:
   ```bash
   cd /path/to/winit-ocaml  # back to main project
   git add rust/vendor/winit  # or rust/vendor/softbuffer
   git commit -m "Update vendored winit to include [feature]"
   ```

7. **Consider upstreaming**: If the changes are generally useful, consider opening a pull
   request to the upstream repository (rust-windowing/winit or rust-windowing/softbuffer).

## Syncing with upstream

To pull in updates from the upstream repositories:

1. **Add upstream remote** (if not already added):
   ```bash
   cd rust/vendor/winit
   git remote add upstream git@github.com:rust-windowing/winit.git
   ```

2. **Fetch and merge** upstream changes:
   ```bash
   git fetch upstream
   git merge upstream/master  # or the appropriate upstream branch
   ```

3. **Push merged changes** to the fork:
   ```bash
   git push origin master
   ```

4. **Update parent repository** to reference the updated commit:
   ```bash
   cd /path/to/winit-ocaml
   git add rust/vendor/winit
   git commit -m "Sync vendored winit with upstream"
   ```
