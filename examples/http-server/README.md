# HTTP server

A single-threaded HTTP/1.1 server built from the embedded `http` codec and the
`network` module's listening resources. It accepts one connection at a time,
reads a complete request, and answers `/` with a small text response. Every
other path is a 404.

```sh
selka build examples/http-server/main.selka -o http-server
./http-server
```

The default build grants every capability. To run it under an explicit grant:

```sh
selka run examples/http-server/main.selka --restrict --allow-listen=127.0.0.1:8080
```

`--allow-listen=IP:PORT` permits only a local listener on that literal endpoint.
It does not permit an outbound connection; a client needs
`--allow-endpoint=IP:PORT`.

The server is intentionally small: it does not parse chunked request bodies,
does not serve concurrent connections, and closes each connection after one
response. Those limits are properties of this example, not of the codec.
