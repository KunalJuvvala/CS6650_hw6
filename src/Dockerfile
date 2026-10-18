# ---- Build stage ----
# If `go build` complains about the Go version, change this tag to match the `go` line in go.mod.
FROM golang:1.27-alpine AS build
WORKDIR /app

# Download deps first so Docker caches them between code changes
COPY go.mod go.sum ./
RUN go mod download

COPY *.go ./
# Static binary so it runs on a tiny base image
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /product-service .

# ---- Run stage ----
FROM alpine:3.20
RUN adduser -D -u 10001 appuser
COPY --from=build /product-service /usr/local/bin/product-service
USER appuser
EXPOSE 8080
ENV PORT=8080
ENTRYPOINT ["/usr/local/bin/product-service"]
