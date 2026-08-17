require('dotenv').config();

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = process.env.PORT || 8080;

const httpServer = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('ok');
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server: httpServer });

wss.on('connection', (clientSocket) => {
  console.log('client connected');

  clientSocket.on('message', (data) => {
    console.log('received message from client, bytes:', data.length);
  });

  clientSocket.on('close', () => {
    console.log('client disconnected');
  });

  clientSocket.on('error', (err) => {
    console.error('client socket error:', err.message);
  });
});

httpServer.listen(PORT, () => {
  console.log(`backend proxy listening on port ${PORT}`);
});
