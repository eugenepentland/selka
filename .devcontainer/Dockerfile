# A Linux x86-64 machine with git and the Zig release that builds Selka. Selka itself is built from the checkout by
# `postCreateCommand` in devcontainer.json (the compiler needs nothing else: Zig carries clang and the linker).
FROM --platform=linux/amd64 debian:stable-slim

# The stable release `.zigversion` names, and the SHA-256 that https://ziglang.org/download/index.json publishes for its
# x86_64-linux tarball. Change both together, and `.zigversion` with them.
ARG ZIG_VERSION=0.17.1
ARG ZIG_SHA256=3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a

RUN apt-get update \
    && apt-get install --yes --no-install-recommends git xz-utils curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --silent --show-error --location --output /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
    && echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum --check - \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz \
    && ln -s /opt/zig/zig /usr/local/bin/zig \
    && zig version
