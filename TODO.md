# 語音對話心理評估 APP — 建置待辦事項

> 最後更新：2026-08-18。接續開發前請先讀這份文件。

## 已確認的技術選型

| 項目 | 選擇 |
|---|---|
| 前端 | Flutter，專案名稱 `voice_bsrs_app`，App ID `com.example.voice_bsrs_app` |
| 後端 | Node.js（`backend/`），部署於 Render Free Tier（Singapore） |
| 音訊播放 | `flutter_sound`（已安裝於 frontend） |
| 錄音 | `record` 套件（已安裝於 frontend） |
| 本地資料庫 | `hive`（尚未安裝，Phase 4 要用） |
| Gemini SDK | 官方 `@google/genai`（已安裝於 backend） |
| Gemini Live 模型 | `gemini-2.5-flash-native-audio-latest`（注意：說明書原寫的 `gemini-2.0-flash-live-001` 和 SDK 範例的 `gemini-live-2.5-flash-preview` 都不可用，是實測目前金鑰能用的模型清單後選定的） |

## 專案位置

- 本機路徑：`E:\NTUH`
- GitHub：https://github.com/ChouTerry-20240925/voice-app （**Public**，使用者已知情並決定先不設 Private）
- Render 後端：https://voice-bsrs-backend.onrender.com （Free Tier，閒置會休眠，喚醒約需 30~50 秒）
- Render 環境變數 `GEMINI_API_KEY` 已設定並驗證可用

## 進度總覽

- [x] **Phase 0：專案初始化**（git init、frontend/backend 目錄、.env 範本）
- [x] **Phase 1：前端介面建置**
  - [x] Step 1：Flutter 專案初始化 + 麥克風/網路權限
  - [x] Step 2：主畫面靜態版（Avatar 預留區、右側三按鈕、開始問答按鈕）
  - [x] Step 3：歷史報表清單頁 + 報表詳情頁 + 備註輸入框（假資料，備註目前只存記憶體）
- [x] **Phase 2：後端 Proxy 建置**
  - [x] Step 1：Node.js 專案初始化 + WebSocket Server 基本框架
  - [x] Step 2：串接 Gemini Live API（`backend/src/geminiLive.js`，雙向轉發音訊 + tool_call）
  - [x] Step 3：本機測試轉發（併入 Step 2 一起測試）
  - [x] Step 4：部署 Render（已驗證 `/health`、WebSocket、Gemini Live 串接皆正常）
- [x] **Phase 3：語音串流整合**
  - [x] Step 1：Flutter 端用 `record` 套件擷取 16kHz PCM，轉 Base64，透過 WebSocket 送到 backend（`frontend/lib/services/voice_session_service.dart`；`RecordConfig` 有開 `echoCancel`/`autoGain`/`noiseSuppress`，沒開的話喇叭聲音會被錄回去造成 Gemini 誤判打斷）
  - [x] Step 2：Flutter 端用 `flutter_sound` 串流播放 backend 轉發回來的音訊（`frontend/lib/services/audio_playback_service.dart`）。**重要教訓**：音訊不能一收到就整包塞進原生播放器緩衝區，也不能固定睡滿每片時長來節流——要用牆上時鐘追蹤「已餵時長 vs. 實際經過時間」，只有領先超過安全值（目前 300ms）才睡，且睡的時長要精算，否則會累積誤差造成破音或緩衝區被掏空
  - [x] Step 3：Avatar 動畫狀態機（傾聽/說話狀態切換，`frontend/lib/main.dart` 的 `_AvatarView` + `_StickFigurePainter`，線條人形依 idle/listening/speaking 呈現不同姿勢與動畫節奏）。狀態切換依據：開始通話→listening、收到音訊（`onAudioChunk`）→speaking、被打斷（`onInterrupted`）→listening、`turn_complete`→listening、結束通話→idle。實機驗證正常
  - [x] Step 4：測試語音延遲、Barge-in（打斷）機制、VAD 靜音容忍度（1.5~2 秒不要太敏感）
    - Barge-in 的 client 端機制（backend 轉發 `serverContent.interrupted`、前端立刻停止播放並丟棄舊音訊）已完成並驗證正常，停止動作約 10ms 內完成
    - **已知待觀察項**：使用者打斷後，Gemini 重新生成新回覆＋語音合成大約要等 3 秒左右，這段是模型端本身的延遲，前端/backend 目前無法縮短，之後如果覺得太久可能要重新檢視 prompt/連線設定
    - `backend/src/geminiLive.js` 的 `realtimeInputConfig.automaticActivityDetection.silenceDurationMs: 1750` 已部署到 Render 並實機驗證，思考停頓不會太容易被誤判打斷
  - [x] checkpoint：實機測試一次完整語音來回
- [ ] **Phase 4：Prompt 設計與報表持久化** ← 接下來從這裡開始
  - [x] Step 1：撰寫 BSRS-5 訪談模式 System Prompt + `generate_report` tool schema，已寫進 `backend/src/geminiLive.js`（`INTERVIEW_SYSTEM_PROMPT`＋`GENERATE_REPORT_TOOL`，用 `Type.OBJECT`/`Type.STRING`/`Type.INTEGER` 而非說明書原文的字串寫法）。內容決策（**非正式醫療專業審閱**，正式使用前建議請心理衛生背景的人再看過措辭）：
    - 第 6 題（自殺意念）用婉轉問法、避開「自殺」字面；偵測到高風險時溫和提醒安心專線 1925，仍完成流程並呼叫 `generate_report`
    - 整個訪談改成「默默進行」：System Prompt 明確要求不要照題號念、不要提到「量表/測驗/檢測」等字眼，讓 6 個面向融入自然聊天中蒐集
    - 連線建立後會呼叫 `session.sendClientContent({...})` 主動觸發 Gemini 開口，讓它照 System Prompt 的【開場】指示先問候（例如「你最近心情怎麼樣？」），不用等使用者先講話。**重要教訓**：一開始用完全空白的 `sendClientContent({ turnComplete: true })` 沒有讓 Gemini 產生回應——SDK 文件說這個空白 nudge 是設計給「沒有開 VAD/realtime audio」的情境用的；我們的連線有開 `automaticActivityDetection`，所以改成塞一則標記為系統事件的假 `user` turn（`[系統事件：...]`）當觸發點才成功，System Prompt 也要補一句告訴模型別把這則訊息當成使用者真的講的話。實機驗證：Gemini 會主動先問候，但需要等一下（幾秒延遲）
    - `frontend/lib/main.dart` 新增 `ConversationMode` 選取狀態：「訪談模式」按鈕現在會真的被選取（有視覺反饋），「專業問答模式」按下去會提示尚未開放。**目前沒選模式時「開始問答」預設走訪談模式**，前端還沒有把選取的模式傳給 backend（因為 backend 目前也只有訪談模式這一種設定），這條線要等 Step 2 專業問答模式做出來後再一起接上
    - **已部署到 Render 並實機驗證**：Gemini 會主動先問候、後續對話自然不像問卷
  - [ ] Step 2：撰寫專業問答模式 System Prompt
  - [x] Step 3：前端接收 `tool_call` 後自動斷線、解析 `report_content`/`total_score`/`result_analysis` 並渲染到報表頁
    - `frontend/lib/services/voice_session_service.dart` 新增 `onToolCall`，`main.dart` 的 `_handleToolCall` 解析 `generate_report` 的 args、建立 `ReportRecord`、結束通話、導到 `ReportDetailScreen`
    - `geminiLive.js` 現在會在轉發 `tool_call` 給前端的同時，也呼叫 `session.sendToolResponse(...)` 回一個簡單的 ack，避免 Gemini 呼叫完 `generate_report` 後等不到回應
    - **已知限制**：新產生的報表目前只會導到報表詳情頁顯示，**不會**出現在「歷史報表」清單（`report_history_screen.dart` 還是讀 `buildFakeReportRecords()` 假資料），要等 Step 4 接上 `hive` 才會真正持久化並出現在清單裡
    - **重要教訓（連線強制關閉問題）**：實測發現連線會在對話進行到「第二輪」左右（不是在 generate_report 附近）就被 API 強制關閉，錯誤是 `The audio content type (CONTENT_TYPE_AUDIO) is not supported for this model configuration`。從 log 追出真正原因：Gemini 這個模型預設會產生 thinking（內部推理）的文字內容（`{"text":"...","thought":true}`），但我們的 `responseModalities` 只允許 `AUDIO`，兩者疑似衝突導致模型接續產生語音時崩潰。修法：加上 `thinkingConfig: { thinkingBudget: 0 }` 關閉 thinking（對即時語音對話本來就不需要，還能降低延遲）。`session.sendToolResponse` 那個修法本身沒錯，只是不是這次連線關閉的真正主因
    - **尚未部署到 Render 實測**，之後要驗證：關閉 thinking 後對話是否能撐到最後、`generate_report` 有沒有正確觸發、報表頁內容是否正確、連線是否乾淨結束
  - [ ] Step 4：`hive` 串接，把報表 JSON + 備註改成真正寫入本地資料庫（目前 `frontend/lib/screens/report_detail_screen.dart` 的備註只存在 State 記憶體裡，重開 App 會消失）
  - checkpoint：完整跑一次「開始問答→BSRS-5 對話→產生報表→寫入本地→查看歷史紀錄」流程
- [ ] **Phase 5：收尾**
  - [ ] 錯誤處理（斷線重連、麥克風權限被拒等邊界情況）
  - [ ] 實機/多裝置驗收

## 重要提醒

- **金鑰安全**：`backend/.env` 放實際金鑰，`.env.example` 只能放佔位值，`.gitignore` 已排除 `.env`（曾經不小心把金鑰打進 `.env.example`，已修正並確認沒進 git 歷史）
- **Render 免費方案**：閒置會休眠，正式 Demo 前需再評估是否升級或加 keep-alive 腳本
- **右側「訪談模式」「專業問答模式」按鈕**目前是空邏輯（no-op），要等 Phase 4 System Prompt 完成後才會真正決定連線時要送哪一種設定
