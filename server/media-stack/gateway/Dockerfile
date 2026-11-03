# syntax=docker/dockerfile:1
# Stage 1: analyze + test + AOT-compile. The build fails if analyze or any test fails.
# Pinned: Dart 3.13.7 (stable) by manifest-list digest.
FROM dart:3.13.7@sha256:517cbeb4612c4dff11c983edea521d5aef3f47a674c23684fad5e89803ca5b1c AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile
COPY analysis_options.yaml ./
COPY bin bin
COPY lib lib
COPY test test
RUN dart analyze --fatal-infos --fatal-warnings \
 && dart test \
 && mkdir -p /out \
 && dart compile exe bin/gateway.dart -o /out/gateway

# Stage 2: distroless (glibc + libstdc++, no shell, no package manager). Pinned by digest.
FROM gcr.io/distroless/cc-debian12@sha256:9dac0a79194e45a7da0158a9c6da57b217585af0786db3845d1f0ec1a0dd182f
COPY --from=build /out/gateway /app/gateway
USER 1000:1000
ENTRYPOINT ["/app/gateway"]
CMD ["serve"]
