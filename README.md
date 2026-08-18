# 語音對話心理評估 APP

全語音互動的心理健康引導介面。使用者透過語音與虛擬人物（Avatar）即時對談，App 內建「訪談模式」（依 BSRS-5 簡式健康量表，透過自然聊天悄悄蒐集六個面向的資訊）與「專業問答模式」（自由心理衛生衛教問答）。訪談結束後由 Gemini 自動產出結構化報表，寫入本機資料庫，供使用者日後查閱、加註備註。

## 功能現況

- **訪談模式**：Gemini 依 System Prompt 主動開場問候，透過自然對話（不提及「量表」「測驗」等字眼）蒐集睡眠困難、焦慮不安、易怒情緒、低落沮喪、自信心低落、負面念頭六個面向，完成後自動呼叫 `generate_report` 工具產出報表並結束通話
- **專業問答模式**：自由心理衛生衛教問答，被動等待使用者開口，不產生報表；超出衛教範圍（如具體醫療診斷、藥物建議）會溫和轉介專業協助
- **報表產生與本地持久化**：報表（含量表分數、逐題摘要、整體評估）透過 Hive 寫入本機資料庫，可在「歷史報表」清單查閱、加註備註，重開 App 資料仍在
- **語音互動細節**：即時雙向語音串流、Barge-in（使用者可隨時打斷模型講話）、Avatar 依對話狀態呈現待機／傾聽／思考中／說話四種姿態動畫（思考中動畫用麥克風音量做本地判斷，純 UI 回饋，不影響實際送給 Gemini 的音訊）
- **錯誤處理**：麥克風權限被拒、連線中（含 Render 免費方案冷啟動提示）、連線意外斷開等邊界情況都有對應畫面回饋

尚未實作／已知限制列在文末「已知限制」一節。

## 系統架構

前端（Flutter）與後端（Node.js）透過 WebSocket 溝通。後端唯一的職責是不讓 Gemini API 金鑰外洩到前端，並轉發 Gemini Live 的雙向語音串流——不含其他商業邏輯。

```
Flutter (錄音 → PCM/Base64) --WebSocket--> Node.js Proxy --Gemini Live API--> Gemini 2.5 Flash
Flutter (音訊播放)          <--WebSocket-- Node.js Proxy <--音訊/tool_call---
```

- **前端**：擷取麥克風音訊（16kHz PCM16）、Base64 編碼後經 WebSocket 送出；即時串流播放收到的回覆音訊；渲染 Avatar 動畫與報表 UI
- **後端**：`backend/src/server.js` 開 WebSocket Server，每個連線對應一個 Gemini Live session；`backend/src/geminiLive.js` 依連線網址的 `?mode=` 參數（`interview` / `qa`）決定要送哪一份 System Prompt 與工具設定，並把 Gemini 的 `serverContent`/`toolCall` 訊息轉譯成前端協定

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
| Gemini Live 模型 | `gemini-2.5-flash-native-audio-latest` |

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
│       └── geminiLive.js            Gemini Live 連線、System Prompt、tool schema
├── TODO.md                         開發進度與技術決策記錄（含教訓/踩雷紀錄）
└── 語音對話心理評估APP開發說明書.md   原始需求規格書
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

## 部署

- **後端**：Render（Singapore region，Free Tier），網址 `https://voice-bsrs-backend.onrender.com`。免費方案閒置約 15 分鐘會休眠，喚醒約需 30~50 秒——前端已加上冷啟動的畫面提示（連線中動畫 + 超過 5 秒顯示喚醒中提示）
- **前端**：目前僅供實機/模擬器手動安裝測試，尚未建立正式發布流程

## 已知限制

- **喜怒哀樂表情**：Avatar 已有繪製喜/怒/哀/樂表情（眉毛角度＋嘴型曲線）的基礎能力，但因為需要真正理解對話語意才能正確選用表情，目前**全部固定為中性表情**，尚未接上任何語意/情緒判斷來源
- **思考動畫閾值**：使用者停頓判斷用固定的絕對分貝門檻，不會依環境噪音自動調整，吵雜環境下可能誤判
- **無真正的斷線重連**：Gemini Live session 的對話狀態存在 session 內，連線意外中斷後只能重新開始一段新對話，無法接續原本的訪談進度（除非日後導入 Gemini 的 session resumption 機制）
- **多裝置驗收未完成**：目前主要在單一 Android 裝置上實機驗證，iOS 僅確認權限宣告已補齊，未實際測試過
- **非正式醫療審閱**：訪談模式與報表的 BSRS-5 相關措辭僅供開發參考，正式上線前建議請具心理衛生背景的人員審閱

## 授權

尚未指定授權條款。
