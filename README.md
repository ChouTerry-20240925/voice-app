# 語音對話心理評估 APP

全語音互動的心理健康引導介面。使用者透過語音與虛擬人物（Avatar）即時對談，App 內建「訪談模式」（依 BSRS-5 簡式健康量表，透過自然聊天悄悄蒐集六個面向的資訊）與「專業問答模式」（自由心理衛生衛教問答）。訪談結束後由 Gemini 自動產出結構化報表，寫入本機資料庫，供使用者日後查閱、加註備註。

## 功能現況

- **訪談模式**：Gemini 依 System Prompt 主動開場問候，透過自然對話（不提及「量表」「測驗」等字眼）蒐集睡眠困難、焦慮不安、易怒情緒、低落沮喪、自信心低落、負面念頭六個面向，完成後自動呼叫 `generate_report` 工具產出報表並結束通話
- **專業問答模式**：自由心理衛生衛教問答，被動等待使用者開口，不產生報表；超出衛教範圍（如具體醫療診斷、藥物建議）會溫和轉介專業協助。掛有 `search_knowledge_base` 工具，可即時查詢台大醫院心臟移植手術後護理指引知識庫（RAG，見下方「RAG 護理知識庫問答」一節），回答時引用標準指引段落。訪談模式不受影響，不掛此工具
- **報表產生與本地持久化**：報表（含量表分數、逐題摘要、整體評估）透過 Hive 寫入本機資料庫，可在「歷史報表」清單查閱、加註備註，重開 App 資料仍在
- **語音互動細節**：即時雙向語音串流、Barge-in（使用者可隨時打斷模型講話）、Avatar 依對話狀態呈現待機／傾聽／思考中／說話四種姿態動畫（思考中動畫用麥克風音量做本地判斷，純 UI 回饋，不影響實際送給 Gemini 的音訊）
- **錯誤處理**：麥克風權限被拒、連線中（含 Render 免費方案冷啟動提示）、連線意外斷開等邊界情況都有對應畫面回饋

尚未實作／已知限制列在文末「已知限制」一節。

## 系統架構

前端（Flutter）與後端（Node.js）透過 WebSocket 溝通。後端唯一的職責是不讓 Gemini API 金鑰外洩到前端，並轉發 Gemini Live 的雙向語音串流——不含其他商業邏輯。

```
Flutter (錄音 → PCM/Base64) --WebSocket--> Node.js Proxy --Gemini Live API--> Gemini 3.1 Flash Live
Flutter (音訊播放)          <--WebSocket-- Node.js Proxy <--音訊/tool_call---
```

- **前端**：擷取麥克風音訊（16kHz PCM16）、Base64 編碼後經 WebSocket 送出；即時串流播放收到的回覆音訊；渲染 Avatar 動畫與報表 UI
- **後端**：`backend/src/server.js` 開 WebSocket Server，每個連線對應一個 Gemini Live session；`backend/src/geminiLive.js` 依連線網址的 `?mode=` 參數（`interview` / `qa`）決定要送哪一份 System Prompt 與工具設定，並把 Gemini 的 `serverContent`/`toolCall` 訊息轉譯成前端協定；QA 模式額外掛有 RAG 查詢工具，詳見下方「RAG 護理知識庫問答」一節

## RAG 護理知識庫問答（專業問答模式）

專業問答模式對話中，Gemini 若判斷使用者的問題需要查閱標準護理指引，會主動呼叫 `search_knowledge_base` 這個 function-calling tool，由後端即時檢索、把相關段落塞回 Gemini 讓它引用著回答。訪談模式（BSRS-5）不受影響，不掛此工具。

```
使用者語音提問
      │
      ▼
Gemini 判斷需要查指引 → 呼叫 search_knowledge_base(query)
      │
      ▼
backend/src/geminiLive.js：攔截 tool_call（不轉發給前端）
      │
      ▼
backend/src/ragService.js
  ├─ OpenAI text-embedding-3-small → 查詢字串轉 1536 維向量
  └─ Supabase RPC match_ntuh_documents（pgvector 相似度搜尋）→ Top-3 相關段落
      │
      ▼
session.sendToolResponse() 把段落文字回傳給 Gemini
      │
      ▼
Gemini 引用指引內容，組織語音回覆
```

- **知識庫內容**：台大醫院心臟移植手術後護理指引，來源語料在 `台大語料整理後/整理後/`（適用對象、例外、護理問題、護理過程各細項、利用資源、參考資料，共 9 個章節、原始文字約 10KB），透過 `ingest_to_supabase.py` 切塊後寫入 Supabase
- **資料表／RPC**：Supabase `ntuh_nursing_documents`（`pgvector` embedding 欄位）+ `match_ntuh_documents` RPC，`match_threshold=0.25`、`match_count=3`（見 `doc/RAG串接.md`）
- **查詢端**：`backend/src/ragService.js`，`SUPABASE_ANON_KEY`（唯讀，RLS 只開放 SELECT）+ `OPENAI_API_KEY`
- **已知限制**：語料量小（9 個章節），`match_threshold`/`match_count` 為初始預設值，尚未依實際問答測試調校；語料若持續擴充，需留意 chunk 品質與 threshold 是否仍適用

## 技術棧

| 項目 | 選擇 |
|---|---|
| 前端 | Flutter（`voice_bsrs_app`），App ID `com.example.voice_bsrs_app` |
| 音訊錄製 | `record` |
| 音訊播放 | `flutter_sound` |
| 本地資料庫 | `hive` + `hive_flutter`（手寫 `TypeAdapter`，未用 code-gen） |
| WebSocket | `web_socket_channel` |
| 後端 | Node.js（`ws` + `http`），部署於 Render Free Tier（Singapore） |
| Gemini SDK | 官方 `@google/genai` |
| Gemini Live 模型 | `gemini-3.1-flash-live-preview`（音色固定為 `Zephyr`，避免模型版本切換時聲線跟著變） |
| 向量資料庫（RAG） | Supabase PostgreSQL + `pgvector`（`ntuh_nursing_documents` 表、`match_ntuh_documents` RPC） |
| Embedding 模型（RAG） | OpenAI `text-embedding-3-small`（1536 維度，查詢端 `backend/src/ragService.js`、批次寫入端 `台大語料整理後/整理後/ingest_to_supabase.py`） |

## 專案結構

```
NTUH/
├── frontend/                       Flutter App
│   └── lib/
│       ├── main.dart                首頁：Avatar、模式選取、通話控制、報表流程
│       ├── models/
│       │   └── report_record.dart   報表資料模型 + 手寫 Hive TypeAdapter
│       ├── screens/
│       │   ├── report_history_screen.dart   歷史報表清單
│       │   └── report_detail_screen.dart    報表詳情 + 備註
│       └── services/
│           ├── voice_session_service.dart   WebSocket 連線、錄音、麥克風音量判斷
│           ├── audio_playback_service.dart  即時串流播放
│           └── report_store.dart            Hive 本地資料庫存取
├── backend/                        Node.js Proxy
│   └── src/
│       ├── server.js                HTTP + WebSocket Server
│       ├── geminiLive.js            Gemini Live 連線、System Prompt、tool schema
│       └── ragService.js            RAG 查詢（OpenAI embedding + Supabase RPC 檢索）
```

## 快速開始

### 後端（`backend/`）

```bash
cd backend
npm install
cp .env.example .env   # 填入實際的 GEMINI_API_KEY
npm start               # node src/server.js，預設監聽 PORT=8080
```

沒有設定 lint/test 腳本。`.env` 已被 `.gitignore` 排除，**絕對不要**把實際金鑰寫進 `.env.example`。

### 前端（`frontend/`）

```bash
cd frontend
flutter pub get
flutter run              # 需要連接實機或啟動模擬器
flutter analyze          # 靜態分析（analysis_options.yaml: flutter_lints）
flutter test             # 執行測試
```

前端目前連線的後端網址是寫死的 `wss://voice-bsrs-backend.onrender.com`（見 `frontend/lib/services/voice_session_service.dart` 的 `kBackendWsUrl`），本機開發需要對應調整或另外跑一份本機 backend。

## 環境變數

| 變數 | 說明 | 設定位置 |
|---|---|---|
| `GEMINI_API_KEY` | Gemini API 金鑰 | `backend/.env`（本機）／Render 環境變數（正式環境，已設定並驗證可用） |
| `PORT` | 後端監聽埠 | `backend/.env`，預設 `8080` |
| `SUPABASE_URL` | Supabase 專案 API 端點（RAG 用） | Render 環境變數（正式環境，已設定） |
| `SUPABASE_ANON_KEY` | Supabase `anon`／唯讀金鑰，`ragService.js` 查詢用（RLS 只開放 SELECT） | Render 環境變數（正式環境，已設定） |
| `OPENAI_API_KEY` | 計算查詢字串 embedding 用 | Render 環境變數（正式環境，已設定） |

## 部署

- **後端**：Render（Singapore region，Free Tier），網址 `https://voice-bsrs-backend.onrender.com`。免費方案閒置約 15 分鐘會休眠，喚醒約需 30~50 秒——前端已加上冷啟動的畫面提示（連線中動畫 + 超過 5 秒顯示喚醒中提示）
- **前端**：目前僅供實機/模擬器手動安裝測試，尚未建立正式發布流程

## 已知限制

- **喜怒哀樂表情**：Avatar 已有繪製喜/怒/哀/樂表情（眉毛角度＋嘴型曲線）的基礎能力，但因為需要真正理解對話語意才能正確選用表情，目前**全部固定為中性表情**，尚未接上任何語意/情緒判斷來源
- **思考動畫閾值**：使用者停頓判斷用固定的絕對分貝門檻，不會依環境噪音自動調整，吵雜環境下可能誤判
- **無真正的斷線重連**：Gemini Live session 的對話狀態存在 session 內，連線意外中斷後只能重新開始一段新對話，無法接續原本的訪談進度（除非日後導入 Gemini 的 session resumption 機制）
- **非正式醫療審閱**：訪談模式與報表的 BSRS-5 相關措辭僅供開發參考，正式上線前建議請具心理衛生背景的人員審閱
- **`gemini-3.1-flash-live-preview` 仍是 preview 版本，偶有不穩定行為**：實測遇過訪談問完一輪後又從頭重問、`generate_report` 從未被呼叫的迴圈狀況，懷疑跟 `contextWindowCompression`（sliding window 壓縮/摘要）與合成的開場系統事件文字互相干擾有關，目前已關閉 `contextWindowCompression` 觀察中（見 `backend/src/geminiLive.js` 註解），尚未完全確認根因，正式環境需持續觀察是否再現
- **`silenceDurationMs` 在此模型上可能被忽略**：Google 官方回報 `automaticActivityDetection.silenceDurationMs` 在 `gemini-3.1-flash-live-preview` 上是已知 bug，設定可能不生效，語音打斷/斷句時機因此無法保證跟 2.5 版一致
- **喇叭外放時的回音誤觸發打斷**：手機用喇叭外放（未戴耳機）測試時，AI 語音會被麥克風重新收音，容易被 Gemini 的 VAD 誤判為使用者插話，導致回覆斷斷續續。`record` 套件雖有開 `echoCancel`，但錄音（`record`）與播放（`flutter_sound`）是兩個獨立的原生音訊 session，AEC 可能拿不到播放端的參考訊號而失效；訪談模式與專業問答模式皆會發生，非 RAG 相關，根因與解法待另外討論（候選方向：改用單一原生音訊管線、建議使用者戴耳機、或軟體層偵測抑制）

## 未來發展

- **喜怒哀樂表情的語意判斷**：延伸現有的 tool-calling 架構（`generate_report` 已驗證過在 `AUDIO` 回覆模式下能穩定夾帶 tool_call），在 System Prompt 加一個輕量工具（例如 `update_emotion(emotion)`），請 Gemini 每輪根據語意判斷後主動呼叫，backend 轉發給前端驅動 Avatar 表情。這樣語意判斷由 Gemini 在既有的對話理解中順便產出，不需額外呼叫模型，也能避開先前開啟 `inputAudioTranscription` 時遇到的時序錯亂問題；取捨是多一個工具呼叫，模型未必每輪都即時或穩定呼叫，需要靠 prompt 調教，且要留意避免重蹈先前 thinking/多模態輸出衝突導致連線被強制關閉的教訓

## 版本紀錄

### v1.0.1

- 升級 Gemini Live 模型：`gemini-2.5-flash-native-audio-latest` → `gemini-3.1-flash-live-preview`，實測回覆延遲明顯改善
- `thinkingConfig` 改用 3.1 的 `thinkingLevel: 'minimal'`（取代 2.5 用的 `thinkingBudget: 0`）
- 新增 `speechConfig`，明確指定 `voiceName: 'Zephyr'`：兩個模型版本各自的預設音色沒有公開文件、且彼此不同，換模型會導致聲線跟著變，改為明確指定後不受模型版本影響
- 修正訪談迴圈問題：關閉 `contextWindowCompression`。原本是為 2.5 版「訪談後段越問越慢」加的 sliding window 壓縮，換到 3.1 後實測出現「訪談問完一輪又從頭重問、`generate_report` 從未被呼叫」的迴圈，懷疑是壓縮/摘要把合成的開場系統事件文字重新帶回 context 前段，讓模型誤判對話重新開始；關閉後測試未再重現，但尚未完全確認根因，正式環境持續觀察中
- 後端新增使用者端音訊接收 log，方便比對延遲與迴圈問題的發生時間點

## 授權

尚未指定授權條款。
