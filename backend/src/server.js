require('dotenv').config();

const http = require('http');
const { WebSocketServer } = require('ws');
const { bridgeClientToGemini } = require('./geminiLive');

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

wss.on('connection', async (clientSocket) => {
  console.log('client connected');

  let geminiSession;
  try {
    geminiSession = await bridgeClientToGemini(clientSocket);
  } catch (err) {
    console.error('failed to connect to gemini live api:', err.message);
    clientSocket.close();
    return;
  }

  clientSocket.on('message', (data) => {
    let message;
    try {
      message = JSON.parse(data.toString());
    } catch (err) {
      console.error('invalid message from client:', err.message);
      return;
    }

    if (message.type === 'audio' && message.data) {
      geminiSession.sendRealtimeInput({
        audio: {
          data: message.data,
          mimeType: message.mimeType || 'audio/pcm;rate=16000',
        },
      });
    }
  });

  clientSocket.on('close', () => {
    console.log('client disconnected');
    geminiSession.close();
  });

  clientSocket.on('error', (err) => {
    console.error('client socket error:', err.message);
  });
});

httpServer.listen(PORT, () => {
  console.log(`backend proxy listening on port ${PORT}`);
});
