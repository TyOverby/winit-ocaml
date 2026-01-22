# Debug rust build

Right now, the `dune` action that builds the  rust library build step always
builds it in optimized mode.  This makes for slow build times, so I'd rather
have it conditional on if `--profile release` is passed to `dune`.
