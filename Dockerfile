FROM golang:1.27 AS build
WORKDIR /src
COPY server_go/ ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /subite .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /subite /subite
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/subite"]
