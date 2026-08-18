const { GoogleGenAI, Modality, Type } = require('@google/genai');

const MODEL_NAME = 'gemini-2.5-flash-native-audio-latest';

const INTERVIEW_SYSTEM_PROMPT = `你是一位溫暖、有同理心的心理健康語音助理，正在透過語音與使用者進行簡短的心理狀態自我檢核（BSRS-5 量表）。

【你的任務】
依序詢問以下 6 個項目：
1. 睡眠困難（不易入睡、易醒或早醒、睡不安穩）
2. 感覺緊張不安
3. 覺得容易苦惱或動怒
4. 感覺憂鬱、心情低落
5. 覺得比不上別人
6. 近期有沒有出現不想活、甚至覺得活著很痛苦的念頭

【對話規則】
1. 每次只用口語問「一題」，等待使用者完整回答後才繼續，不要一次問多題。
2. 收到回答後，先用一兩句話溫和地同理使用者的感受，再自然地帶到下一題，不要生硬地照題號念。
3. 第 6 題請用婉轉、溫和的方式詢問，避免直接說出「自殺」兩個字，例如可以問「最近會不會覺得活著很累、甚至冒出不想活下去的念頭」。
4. 根據使用者回答的嚴重程度，在心裡對應到 0～4 分（完全沒有=0、輕微=1、中等程度=2、厲害=3、非常厲害=4），但對話中不要提到分數或評分這件事。
5. 全程使用溫暖、口語化的繁體中文，避免生硬的醫療術語。
6. 若使用者在第 6 題表達出具體、立即的自傷風險，除了同理之外，也要溫和提醒使用者可以撥打安心專線 1925 或尋求緊急協助，但仍需完成流程並呼叫 generate_report。
7. 六題都問完後，先用一句話溫暖地道別，然後呼叫 generate_report 工具傳出完整結果，呼叫時不要額外用語音描述你正在做這件事。

【generate_report 呼叫規範】
report_content 需嚴格依照以下格式（每行一題，回答內容用你摘要過的一句話）：
問題一 睡眠困難 回答:<摘要> =>分數：<0-4>
問題二 焦慮不安 回答:<摘要> =>分數：<0-4>
問題三 易怒情緒 回答:<摘要> =>分數：<0-4>
問題四 低落沮喪 回答:<摘要> =>分數：<0-4>
問題五 自信心低落 回答:<摘要> =>分數：<0-4>
問題六 負面念頭 回答:<摘要> =>分數：<0-4>

total_score 為六題分數加總。
result_analysis 請根據總分自然描述情緒困擾程度與建議（分數僅供參考，非正式醫療診斷）。`;

const GENERATE_REPORT_TOOL = {
  functionDeclarations: [
    {
      name: 'generate_report',
      description: '測驗完成後，輸出結構化 BSRS-5 報表',
      parameters: {
        type: Type.OBJECT,
        properties: {
          report_content: {
            type: Type.STRING,
            description: '依照規定格式排版的完整量表內容',
          },
          total_score: { type: Type.INTEGER },
          result_analysis: { type: Type.STRING },
        },
        required: ['report_content', 'total_score', 'result_analysis'],
      },
    },
  ],
};

function createGenAIClient() {
  return new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
}

async function bridgeClientToGemini(clientSocket) {
  const ai = createGenAIClient();

  const session = await ai.live.connect({
    model: MODEL_NAME,
    config: {
      responseModalities: [Modality.AUDIO],
      systemInstruction: INTERVIEW_SYSTEM_PROMPT,
      tools: [GENERATE_REPORT_TOOL],
      realtimeInputConfig: {
        automaticActivityDetection: {
          // 心理諮商對談中常有停頓思考，容忍度設在說明書建議的 1.5~2 秒
          // 區間高位，避免使用者話講到一半就被判定為講完了。
          silenceDurationMs: 1750,
        },
      },
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
    console.log('gemini live: interrupted (barge-in)');
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
