// Forwarder for OpenScience's loopback-only server.
//
// OpenScience binds to 127.0.0.1 and rejects any request whose Host header
// isn't localhost/127.0.0.1 (DNS-rebinding defense, no remote mode upstream).
// This proxy listens on 0.0.0.0 so Docker can publish the port, and rewrites
// Host to the loopback value the guard expects. The Origin header passes
// through untouched — the upstream Origin guard still applies, extended via
// OPENSCIENCE_CORS_DOMAINS (e.g. your tailnet: tailXXXX.ts.net).
const http = require('http');

const LISTEN_PORT = Number(process.env.OPENSCIENCE_LISTEN_PORT || 3000);
const INTERNAL_PORT = Number(process.env.OPENSCIENCE_INTERNAL_PORT || 4096);

const server = http.createServer((req, res) => {
  const headers = { ...req.headers, host: `127.0.0.1:${INTERNAL_PORT}` };
  delete headers.connection;

  const upstream = http.request(
    { host: '127.0.0.1', port: INTERNAL_PORT, method: req.method, path: req.url, headers },
    (upRes) => {
      res.writeHead(upRes.statusCode, upRes.headers);
      upRes.pipe(res);
    }
  );
  upstream.on('error', () => {
    res.writeHead(502, { 'content-type': 'text/plain' });
    res.end('openscience server unavailable');
  });
  req.pipe(upstream);
});

server.listen(LISTEN_PORT, '0.0.0.0', () => {
  console.log(`proxy: 0.0.0.0:${LISTEN_PORT} -> 127.0.0.1:${INTERNAL_PORT} (Host rewritten)`);
});
