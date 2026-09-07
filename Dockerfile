FROM golang:1.22-bookworm AS builder
WORKDIR /src
COPY go.mod config.json.tpl main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags='-s -w' -o /configgen .

FROM ghcr.io/xtls/xray-core:__XRAY_VERSION__
COPY --from=builder /configgen /configgen
COPY config.json.tpl /config.json.tpl
EXPOSE 8080
USER nobody
ENTRYPOINT ["/configgen"]
