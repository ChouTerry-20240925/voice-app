const { GoogleGenAI, Modality, Type } = require('@google/genai');

const MODEL_NAME = 'gemini-2.5-flash-native-audio-latest';

const INTERVIEW_SYSTEM_PROMPT = `你是一位溫暖、有同理心的心理健康語音助理。使用者不知道你正在進行心理狀態檢核，你要用自然聊天的方式，悄悄地在對話中蒐集判斷 BSRS-5 六個面向所需要的資訊，全程不要讓對話感覺像是在做問卷、測驗或檢測。

【開場】
連線建立後不用等使用者先開口，由你主動先開口。用一句自然、溫暖的問候語開場，例如「你最近心情怎麼樣？」，不要提到「檢測」「量表」「測驗」之類的字眼。對話一開始你會看到一則用中括號標記的系統事件訊息（例如「[系統事件：...]」），那不是使用者說的話，只是提示你可以開口了，不要對它做出任何回應或提及它。

【你要蒐集的 6 個面向】（透過自然對話逐步了解，不要照編號念出來，也不要讓使用者發現你在照表操課）
1. 睡眠困難（不易入睡、易醒或早醒、睡不安穩）
2. 感覺緊張不安
3. 覺得容易苦惱或動怒
4. 感覺憂鬱、心情低落
5. 覺得比不上別人
6. 近期有沒有出現不想活、甚至覺得活著很痛苦的念頭

【對話規則】
1. 順著使用者原本在講的內容自然接話、追問，像朋友聊天一樣，不要為了湊滿六個面向就生硬地換話題。
2. 每次口語互動只聚焦一個重點，等使用者完整回應、你也同理回應完後，才自然帶到下一個面向。
3. 每次收到回答後，先用一兩句話溫和地同理使用者的感受，再自然銜接下去。
4. 談到第 6 個面向（自殺意念）時，用婉轉、溫和的方式詢問，避免直接說出「自殺」兩個字，例如可以問「最近會不會覺得活著很累、甚至冒出不想活下去的念頭」。
5. 根據使用者回答的嚴重程度，在心裡對應到 0～4 分（完全沒有=0、輕微=1、中等程度=2、厲害=3、非常厲害=4），全程不要在對話中提到分數、評分、量表、檢測等字眼。
6. 全程使用溫暖、口語化的繁體中文，避免生硬的醫療術語。
7. 若使用者表達出具體、立即的自傷風險，除了同理之外，也要溫和提醒使用者可以撥打安心專線 1925 或尋求緊急協助，但仍需完成蒐集並呼叫 generate_report。
8. 當你已經透過對話自然地了解完六個面向後，用一句話溫暖地道別，然後呼叫 generate_report 工具傳出完整結果，呼叫時不要額外用語音描述你正在做這件事。

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

  // Declared before connect() (not `const session = await ...`) so the
  // onmessage callback's closure can reference it — by the time any real
  // message arrives (after setup completes and our opening nudge below is
  // sent), this will already be assigned.
  let session;

  session = await ai.live.connect({
    model: MODEL_NAME,
    config: {
      responseModalities: [Modality.AUDIO],
      systemInstruction: INTERVIEW_SYSTEM_PROMPT,
      tools: [GENERATE_REPORT_TOOL],
      // Thinking output is text ("thought" parts), which seems to be
      // incompatible with an audio-only responseModalities config — the
      // session errored out and force-closed right after emitting one.
      // We don't need chain-of-thought for a conversational voice
      // assistant anyway, and skipping it also cuts response latency.
      thinkingConfig: { thinkingBudget: 0 },
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
        console.log('gemini message:', JSON.stringify(message).slice(0, 500));
        forwardGeminiMessageToClient(message, clientSocket, session);
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

  // Nudge Gemini to speak first per INTERVIEW_SYSTEM_PROMPT's 【開場】
  // instruction, instead of silently waiting for the user's first turn. An
  // entirely empty turnComplete-only call didn't reliably produce a
  // response when automaticActivityDetection is also enabled, so this
  // seeds a minimal synthetic turn — framed as a system event, not
  // something the user actually said — to give the model something
  // concrete to react to.
  console.log('sending opening nudge to gemini');
  session.sendClientContent({
    turns: [
      {
        role: 'user',
        parts: [{ text: '[系統事件：語音通話剛連線，使用者尚未發言，請依照你的開場指示主動開口]' }],
      },
    ],
    turnComplete: true,
  });

  return session;
}

function forwardGeminiMessageToClient(message, clientSocket, session) {
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

    // Acknowledge the call so Gemini isn't left waiting for a response it
    // never gets — without this the session errors out and force-closes
    // once the model tries to continue after calling generate_report.
    // generate_report only hands data to the client; there's nothing for
    // the server to actually execute, so the response is a bare ack.
    session.sendToolResponse({
      functionResponses: message.toolCall.functionCalls.map((call) => ({
        id: call.id,
        name: call.name,
        response: { output: { success: true } },
      })),
    });
  }
}

module.exports = { bridgeClientToGemini, MODEL_NAME };
