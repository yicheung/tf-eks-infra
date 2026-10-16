# syntax=docker/dockerfile:1
# Pin both base images by digest (Dependabot keeps the digests current):
#   docker buildx imagetools inspect golang:1.26-alpine --format '{{json .Manifest.Digest}}'

FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/sample-app .

# distroless/static: no shell, no package manager, runs as UID 65532.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/sample-app /sample-app
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/sample-app"]
