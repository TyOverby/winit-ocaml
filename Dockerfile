# Dockerfile to build sdf/neon/neon.exe (Linux, release profile).
#
# Build from the repo root:
#   docker build -t ty-mono-neon .
#
# The resulting executable lives at /src/_build/default/sdf/neon/neon.exe
# inside the image. To pull it out:
#   docker create --name neon ty-mono-neon
#   docker cp neon:/src/_build/default/sdf/neon/neon.exe ./neon.exe
#   docker rm neon

FROM ubuntu:24.04

# --- Non-interactive apt + opam-as-root settings -------------------------------
ENV DEBIAN_FRONTEND=noninteractive \
    OPAMROOTISOK=1 \
    OPAMYES=1

# --- 3 + system deps: build toolchain, opam, and the native libs that --------
#     winit/softbuffer link against (X11 / Wayland / xkbcommon). -----------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      build-essential \
      autoconf \
      automake \
      libtool \
      pkg-config \
      m4 \
      unzip \
      rsync \
      opam \
      clang \
      libclang-dev \
      libgmp-dev \
      libffi-dev \
      zlib1g-dev \
      libxcb1-dev \
      libx11-dev \
      libxkbcommon-dev \
      libwayland-dev \
    && rm -rf /var/lib/apt/lists/*

# --- 3 install rust (stable; edition 2024 in this repo needs a recent rustc) ---
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain stable --profile minimal \
    && rustc --version && cargo --version

# --- 1 import repo contents ----------------------------------------------------
WORKDIR /src
COPY . /src

# --- 2 initialize / fetch submodules -------------------------------------------
# .gitmodules uses git@github.com: (SSH) URLs; rewrite to HTTPS so they can be
# fetched without SSH credentials inside the build. neon.exe needs the winit and
# softbuffer crates, and vendor/wgpu-native is a Cargo workspace member (its
# manifest must exist for any cargo build in the workspace).
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" \
    && git submodule update --init --recursive \
        vendor/winit vendor/softbuffer vendor/wgpu-native

# --- 4 install opam + create the OxCaml switch ---------------------------------
RUN opam init --bare --disable-sandboxing --yes \
    && opam switch create ./ 5.2.0+ox \
        --repos ox=git+https://github.com/oxcaml/opam-repository.git,default

# --- 5 install ocaml dependencies (rust deps are built automatically by dune) --
RUN opam install --yes \
      dune \
      ppx_jane \
      ppx_builtin \
      base \
      stdio \
      core \
      core_unix \
      yaml \
      gg \
      parallel \
      unboxed \
      menhir \
      lrgrep.0.3

# --- 6 build the linux executable ----------------------------------------------
RUN opam exec -- dune build sdf/neon/neon.exe --profile=release

CMD ["/src/_build/default/sdf/neon/neon.exe"]
