FROM rust:1.84-slim-bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends git ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

ARG SCCACHE_VERSION=0.10.0
RUN ARCH=$(uname -m); \
    case "$ARCH" in \
        x86_64)  SCCACHE_ARCH=x86_64-unknown-linux-musl ;; \
        aarch64) SCCACHE_ARCH=aarch64-unknown-linux-musl ;; \
        *) echo "unsupported arch: $ARCH" && exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}.tar.gz" \
        | tar xz -C /tmp && \
    mv /tmp/sccache-*/sccache /usr/local/bin/sccache && \
    chmod +x /usr/local/bin/sccache && \
    rm -rf /tmp/sccache-*

ENV SCCACHE_DIR=/sccache-cache
ENV CARGO_TERM_COLOR=always

WORKDIR /repro
COPY workspace ./workspace
COPY repro.sh  ./repro.sh
RUN chmod +x ./repro.sh

ENTRYPOINT ["/repro/repro.sh"]
