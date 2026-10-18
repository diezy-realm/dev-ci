# CI image for bin/ci-poller (one-shot `docker run`, no GitHub Actions runner).
# Toolchain versions come from rust-toolchain.toml (rustup installs on first use).
FROM ubuntu:24.04

ARG NEXTEST_VERSION=0.9.148
ARG NEXTEST_SHA256=223ba936714cc861a9cdedad5a8eb664dfdd69d6fbdf6cea6aa8184f523290dc
ARG DENY_VERSION=0.19.9
ARG DENY_SHA256=f1f8eedc2a3ac297c540873f93785d4104b102c0079506b2a6b3221b7ec956af
ARG SCCACHE_VERSION=0.18.0
ARG SCCACHE_SHA256=45f1447fbe231e3037bde351ef70677dd212216c8d62ae7ca409fecc4d6acc89
ARG AUDIT_VERSION=0.22.2
ARG AUDIT_SHA256=ab28a1bdb54db4d5d8ad5981cf1f959410370b3d28250dbd35f6a44248620e39

ENV DEBIAN_FRONTEND=noninteractive
# protobuf-compiler: clawcrew-gateway/build.rs needs protoc (the old runner image lacked it).
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential clang mold cmake protobuf-compiler pkg-config libssl-dev libudev-dev \
        ca-certificates curl git jq ripgrep expect gettext python3 python3-pip python3-yaml \
        nodejs npm unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 1001 --shell /bin/bash runner \
    && mkdir /ci-target /sccache && chown runner:runner /ci-target /sccache
USER runner
WORKDIR /home/runner

ENV CARGO_HOME=/home/runner/.cargo \
    RUSTUP_HOME=/home/runner/.rustup \
    PATH=/home/runner/.cargo/bin:$PATH \
    SCCACHE_DIR=/sccache \
    SCCACHE_CACHE_SIZE=20G
# .cargo/config.toml owns `rustc-wrapper = "sccache"`; the image only provides the binary and cache dir.

# rustup with no default toolchain: rust-toolchain.toml selects the pinned one.
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain none \
    && set -e; \
    fetch() { curl -fsSL "$1" -o /tmp/dl && echo "$2  /tmp/dl" | sha256sum -c -; }; \
    fetch "https://github.com/nextest-rs/nextest/releases/download/cargo-nextest-${NEXTEST_VERSION}/cargo-nextest-${NEXTEST_VERSION}-x86_64-unknown-linux-gnu.tar.gz" "$NEXTEST_SHA256" \
        && tar -xzf /tmp/dl -C "$CARGO_HOME/bin"; \
    fetch "https://github.com/EmbarkStudios/cargo-deny/releases/download/${DENY_VERSION}/cargo-deny-${DENY_VERSION}-x86_64-unknown-linux-musl.tar.gz" "$DENY_SHA256" \
        && tar -xzf /tmp/dl -C "$CARGO_HOME/bin" --strip-components=1; \
    fetch "https://github.com/rustsec/rustsec/releases/download/cargo-audit%2Fv${AUDIT_VERSION}/cargo-audit-x86_64-unknown-linux-gnu-v${AUDIT_VERSION}.tgz" "$AUDIT_SHA256" \
        && tar -xzf /tmp/dl -C "$CARGO_HOME/bin" --strip-components=1; \
    fetch "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl.tar.gz" "$SCCACHE_SHA256" \
        && tar -xzf /tmp/dl -C "$CARGO_HOME/bin" --strip-components=1 "sccache-v${SCCACHE_VERSION}-x86_64-unknown-linux-musl/sccache"; \
    rm -f /tmp/dl

# The poller mounts a per-PR volume here and caches at these paths; they must pre-exist so Docker
# keeps them owned by `runner`.
RUN mkdir -p .cargo/registry actions-runner/_work

COPY --chmod=0755 trim-target.sh /usr/local/bin/
