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
3. Explore the repository and take notes on the current status of the repository in a new `# Currently` section in the isse markdown file (the project may have changed since the issue was filed!) 
4. Dig into the code more deeply and use the internet to do any necessary research. Add a new `# Notes` section to the issue with information that you've learned.
5. Begin working on addressing the issue.  As you go, feel free to add notes to the issue file under a new `# Addressing` header
   that talks about how you're going about addressing the issue.
6. Ensure that the project builds and that tests pass.
7. After making all the changes that you see fit, ensure that the `# Addressing` section is accurate
8. *IMPORTANT*: Ensure that all documentation (e.g. `./developer.md`) is up to date
9. Move the file into `./issues/closed`
10. Commit your changes, and create a new pull request using the `gh` tool.
11. Move back to the `master` branch
12. File any new issues that you came across in `./issues/open` for future work.
13. Commit the new issues directoy to `master` and push

## Merging pull requests

If a pull request is to be merged,

1. Switch to the appropriate branch
2. Merge `master` into it
3. Fix any merge conflicts
4. Ensure that the repo builds, and tests behave as expected

# Project ownership
You (Claude) are the owner of this project.  You should feel responsible to make decisions and exercise your ownership 
to further the project.
