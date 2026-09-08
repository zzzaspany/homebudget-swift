# syntax=docker/dockerfile:1

# The client is compiled to WebAssembly in its own stage. It needs the Swift SDK for
# wasm32-unknown-wasi, which is a large download, so keeping it here means the runtime image never
# carries it and the layer is reused whenever only server code changes.
FROM docker.io/library/swift:6.3.3-noble AS wasm

ARG WASM_SDK_URL=https://download.swift.org/swift-6.3.3-release/wasm-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_wasm.artifactbundle.tar.gz
ARG WASM_SDK_CHECKSUM=cabfa08b73bb8ac783927ecd15fa386e99d0c139c5f232445067bcf58379cae7

# Fetched with curl rather than left to `swift sdk install`, whose downloader gives up after a
# minute with no retry. That is enough for the best part of a gigabyte on a fast link but not
# under Apple's `container`, whose VM networking timed out here every time.
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
RUN curl --location --fail --show-error --silent \
    --retry 5 --retry-delay 5 --retry-all-errors --continue-at - \
    --output /tmp/wasm-sdk.tar.gz "$WASM_SDK_URL" \
    && swift sdk install /tmp/wasm-sdk.tar.gz --checksum "$WASM_SDK_CHECKSUM" \
    && rm -f /tmp/wasm-sdk.tar.gz

WORKDIR /build
COPY Packages/HomeBudgetCore Packages/HomeBudgetCore
COPY Packages/WebClient Packages/WebClient

WORKDIR /build/Packages/WebClient
RUN swift package --swift-sdk swift-6.3.3-RELEASE_wasm \
    --allow-writing-to-package-directory js -c release --output /wasm-bundle


# The Vapor binary.
FROM docker.io/library/swift:6.3.3-noble AS server

WORKDIR /build
COPY Packages/HomeBudgetCore Packages/HomeBudgetCore
COPY Packages/Server Packages/Server

WORKDIR /build/Packages/Server
# Resolve dependencies as their own layer, so editing source does not refetch them.
RUN swift package resolve
RUN swift build -c release --static-swift-stdlib -Xlinker -no-pie


# Runtime. The Swift runtime is linked statically above, so this needs no toolchain.
FROM docker.io/library/ubuntu:noble

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata libcurl4 libxml2 \
    && rm -rf /var/lib/apt/lists/*

# The app writes only to its uploads volume, so it need not run as root.
RUN useradd --user-group --create-home --home-dir /app homebudget
WORKDIR /app

COPY --from=server --chown=homebudget:homebudget /build/Packages/Server/.build/release/App ./App
COPY --from=server --chown=homebudget:homebudget /build/Packages/Server/Resources ./Resources
COPY --from=server --chown=homebudget:homebudget /build/Packages/Server/Public ./Public
COPY --from=wasm --chown=homebudget:homebudget /wasm-bundle ./Public/app

RUN mkdir -p /app/data/uploads && chown -R homebudget:homebudget /app/data

USER homebudget
EXPOSE 8000

# Stamped by CI from the git tag, so a running container can say which build it is.
ARG APP_VERSION=dev

ENV PORT=8000 \
    INVOICE_STORAGE_PATH=/app/data/uploads \
    APP_VERSION=${APP_VERSION}

ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8000"]
