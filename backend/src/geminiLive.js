const { GoogleGenAI, Modality } = require('@google/genai');

const MODEL_NAME = 'gemini-2.5-flash-native-audio-latest';

function createGenAIClient() {
  return new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
}

async function bridgeClientToGemini(clientSocket) {
  const ai = createGenAIClient();

  const session = await ai.live.connect({
    model: MODEL_NAME,
    config: {
      responseModalities: [Modality.AUDIO],
    },
    callbacks: {
      onopen: () => {
        console.log('gemini live session opened');
      },
      onmessage: (message) => {
        forwardGeminiMessageToClient(message, clientSocket);
      },
      onerror: (event) => {
        console.error('gemini live error:', event?.message || event);
      },
      onclose: (event) => {
        console.log('gemini live session closed:', event?.reason || '');
        if (clientSocket.readyState === clientSocket.OPEN) {
          clientSocket.close();
        }
      },
    },
  });

  return session;
}

function forwardGeminiMessageToClient(message, clientSocket) {
  if (clientSocket.readyState !== clientSocket.OPEN) return;

  const modelTurn = message.serverContent?.modelTurn;
  if (modelTurn?.parts) {
    for (const part of modelTurn.parts) {
      if (part.inlineData?.data) {
        clientSocket.send(
          JSON.stringify({
            type: 'audio',
            data: part.inlineData.data,
            mimeType: part.inlineData.mimeType,
          })
        );
      }
    }
  }

  if (message.serverContent?.interrupted) {
    clientSocket.send(JSON.stringify({ type: 'interrupted' }));
  }

  if (message.serverContent?.turnComplete) {
    clientSocket.send(JSON.stringify({ type: 'turn_complete' }));
  }

  if (message.toolCall?.functionCalls) {
    clientSocket.send(
      JSON.stringify({
        type: 'tool_call',
        functionCalls: message.toolCall.functionCalls,
      })
    );
  }
}

module.exports = { bridgeClientToGemini, MODEL_NAME };
