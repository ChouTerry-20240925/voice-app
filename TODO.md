# 語音對話心理評估 APP — 建置待辦事項

> 最後更新：2026-08-18。接續開發前請先讀這份文件。

## 已確認的技術選型

| 項目 | 選擇 |
|---|---|
| 前端 | Flutter，專案名稱 `voice_bsrs_app`，App ID `com.example.voice_bsrs_app` |
| 後端 | Node.js（`backend/`），部署於 Render Free Tier（Singapore） |
| 音訊播放 | `flutter_sound`（已安裝於 frontend） |
| 錄音 | `record` 套件（已安裝於 frontend） |
| 本地資料庫 | `hive` + `hive_flutter`（已安裝於 frontend，手寫 `TypeAdapter`，未用 `hive_generator`/`build_runner`） |
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
    - **後續補上第 4 個狀態 `thinking`**（Phase 4 測試階段使用者反應「說完話後停頓會等很久、不知道是不是在處理」才加的）：使用者停頓時顯示「手托下巴 + 頭上三個依序跳動的點」。判斷邏輯在 `voice_session_service.dart`，用雙門檻（-30dB 進入「說話」、-40dB 才確認「安靜」中間留死區）＋防抖，音量直接從送給後端的 PCM16 chunk 自己算 peak dBFS——一開始改用 `record` 套件內建的 `onAmplitudeChanged`，但在 `startStream()` 串流模式下該 API 沒有正確回報數值，思考動畫完全不會觸發，才改成自己算。純前端本地判斷，不影響實際送給 Gemini 的音訊
      - 防抖時間調整過幾次：一開始怕誤判用 1500ms（太慢，使用者反應「不會觸發」，後來查出是 `onAmplitudeChanged` 本身沒回報數值，跟防抖無關）→ 改自己算音量後改成 400ms（求即時安心感，不追求精準對齊 Gemini 的判斷時機）→ 又發現「思考中跳回聆聽」完全沒防抖，單一雜音就會打斷，補上對稱的 250ms 確認延遲（`_speechConfirmDelay`）
      - **已知限制（討論後決定先不處理）**：門檻是寫死的絕對分貝值（-30dB/-40dB），不會依環境噪音自動調整，吵雜環境下可能會誤判或動畫遲遲不出現/不消失。因為這只是 UI 回饋動畫、不影響實際對話（Gemini 自己在伺服器端的語音偵測是獨立邏輯），且這個 App 主要用途是安靜環境下的心理訪談，先接受這個限制，如果之後有吵雜環境使用的需求，可以考慮改成通話開始時先量一段環境噪音、門檻改成相對噪音底的偏移量
  - [x] Step 4：測試語音延遲、Barge-in（打斷）機制、VAD 靜音容忍度（1.5~2 秒不要太敏感）
    - Barge-in 的 client 端機制（backend 轉發 `serverContent.interrupted`、前端立刻停止播放並丟棄舊音訊）已完成並驗證正常，停止動作約 10ms 內完成
    - **已知待觀察項**：使用者打斷後，Gemini 重新生成新回覆＋語音合成大約要等 3 秒左右，這段是模型端本身的延遲，前端/backend 目前無法縮短，之後如果覺得太久可能要重新檢視 prompt/連線設定
    - `backend/src/geminiLive.js` 的 `realtimeInputConfig.automaticActivityDetection.silenceDurationMs` 一開始設 1750，已部署並實機驗證思考停頓不會太容易被誤判打斷。**後續（Phase 4 測試階段）發現這個值調太保守**：查證 Gemini Live API 官方文件後，伺服器內部預設約 800ms、建議範圍 500~800ms，1750ms 遠超出建議範圍，是造成使用者反應「回覆等很久（甚至忍不住問還在嗎）」的主因之一，已調整為建議範圍內的 650ms（見 Phase 4 記錄）
  - [x] checkpoint：實機測試一次完整語音來回
- [x] **Phase 4：Prompt 設計與報表持久化**
  - [x] Step 1：撰寫 BSRS-5 訪談模式 System Prompt + `generate_report` tool schema，已寫進 `backend/src/geminiLive.js`（`INTERVIEW_SYSTEM_PROMPT`＋`GENERATE_REPORT_TOOL`，用 `Type.OBJECT`/`Type.STRING`/`Type.INTEGER` 而非說明書原文的字串寫法）。內容決策（**非正式醫療專業審閱**，正式使用前建議請心理衛生背景的人再看過措辭）：
    - 第 6 題（自殺意念）用婉轉問法、避開「自殺」字面；偵測到高風險時溫和提醒安心專線 1925，仍完成流程並呼叫 `generate_report`
    - 整個訪談改成「默默進行」：System Prompt 明確要求不要照題號念、不要提到「量表/測驗/檢測」等字眼，讓 6 個面向融入自然聊天中蒐集
    - 連線建立後會呼叫 `session.sendClientContent({...})` 主動觸發 Gemini 開口，讓它照 System Prompt 的【開場】指示先問候（例如「你最近心情怎麼樣？」），不用等使用者先講話。**重要教訓**：一開始用完全空白的 `sendClientContent({ turnComplete: true })` 沒有讓 Gemini 產生回應——SDK 文件說這個空白 nudge 是設計給「沒有開 VAD/realtime audio」的情境用的；我們的連線有開 `automaticActivityDetection`，所以改成塞一則標記為系統事件的假 `user` turn（`[系統事件：...]`）當觸發點才成功，System Prompt 也要補一句告訴模型別把這則訊息當成使用者真的講的話。實機驗證：Gemini 會主動先問候，但需要等一下（幾秒延遲）
    - `frontend/lib/main.dart` 新增 `ConversationMode` 選取狀態：「訪談模式」按鈕現在會真的被選取（有視覺反饋），「專業問答模式」按下去會提示尚未開放。**目前沒選模式時「開始問答」預設走訪談模式**，前端還沒有把選取的模式傳給 backend（因為 backend 目前也只有訪談模式這一種設定），這條線要等 Step 2 專業問答模式做出來後再一起接上
    - **已部署到 Render 並實機驗證**：Gemini 會主動先問候、後續對話自然不像問卷
  - [x] Step 2：撰寫專業問答模式 System Prompt，已寫進 `backend/src/geminiLive.js`（`QA_SYSTEM_PROMPT`）。內容決策（使用者確認）：話題不設嚴格邊界（先直接套模型，保留修改空間）、超出衛教範圍（如具體醫療診斷/藥物建議）時溫和轉介專業協助、不呼叫 `generate_report`／不產生報表、被動等待使用者先開口（不像訪談模式會主動開場）
    - `bridgeClientToGemini(clientSocket, mode)` 依 `mode`（`'interview'` | `'qa'`）切換 systemInstruction/是否掛 `GENERATE_REPORT_TOOL`/是否送開場 nudge；`backend/src/server.js` 從 WebSocket 連線網址的 `?mode=` 讀取
    - 前端 `frontend/lib/services/voice_session_service.dart` 的 `start()` 加上 `mode` 參數並接到連線網址；`main.dart` 的「專業問答模式」按鈕改成真的可選取（拿掉原本「尚未開放」的提示）
    - 已部署到 Render 並實機驗證整體流程可用
  - [x] Step 3：前端接收 `tool_call` 後自動斷線、解析 `report_content`/`total_score`/`result_analysis` 並渲染到報表頁
    - `frontend/lib/services/voice_session_service.dart` 新增 `onToolCall`，`main.dart` 的 `_handleToolCall` 解析 `generate_report` 的 args、建立 `ReportRecord`
    - `geminiLive.js` 現在會在轉發 `tool_call` 給前端的同時，也呼叫 `session.sendToolResponse(...)` 回一個簡單的 ack，避免 Gemini 呼叫完 `generate_report` 後等不到回應
    - **已知限制**：新產生的報表目前只會導到報表詳情頁顯示，**不會**出現在「歷史報表」清單（`report_history_screen.dart` 還是讀 `buildFakeReportRecords()` 假資料），要等 Step 4 接上 `hive` 才會真正持久化並出現在清單裡
    - **重要教訓（連線強制關閉問題，已修復並實機驗證）**：實測發現連線會在對話進行到「第二輪」左右（不是在 generate_report 附近）就被 API 強制關閉，錯誤是 `The audio content type (CONTENT_TYPE_AUDIO) is not supported for this model configuration`。從 log 追出真正原因：Gemini 這個模型預設會產生 thinking（內部推理）的文字內容（`{"text":"...","thought":true}`），但我們的 `responseModalities` 只允許 `AUDIO`，兩者疑似衝突導致模型接續產生語音時崩潰。修法：加上 `thinkingConfig: { thinkingBudget: 0 }` 關閉 thinking（對即時語音對話本來就不需要，還能降低延遲）。**已部署到 Render 並實機驗證通過**：對話能撐到最後、`generate_report` 正確觸發、連線乾淨結束
    - **重要教訓（報表彈窗跳出太快）**：原本收到 `tool_call` 就立刻掛斷/跳轉，但 System Prompt 要求模型呼叫 `generate_report` 前會先講一句道別語音，導致道別還沒播完畫面就跳走。修法：收到 `tool_call` 先記住報表資料、不掛斷；`AudioPlaybackService` 新增 `waitUntilIdle()`（等佇列音訊真正播完，不只是「收到」），等 `turn_complete` 且播放完畢後才結束通話，彈出「對話已完成」對話框讓使用者點「查看報表詳情」才導頁；另外加了 `onDisconnected` 保險，避免連線意外斷掉、`turn_complete` 沒送到時卡住。已實機驗證
  - [x] Step 4：`hive` 串接，把報表 JSON + 備註改成真正寫入本地資料庫
    - `frontend/lib/models/report_record.dart` 加上手寫 `ReportRecordAdapter`（`TypeAdapter<ReportRecord>`），沒用 `hive_generator`/`build_runner`——欄位少又穩定，手寫比較省事
    - 新增 `frontend/lib/services/report_store.dart` 包住 Hive box 存取（`init()`/`getAll()`/`save()`）；`main()` 改成 async，先 `await ReportStore.init()` 再 `runApp()`
    - `main.dart` 的 `_handleToolCall` 收到 `tool_call` 就立刻 `ReportStore.save()` 寫入（不等彈窗流程跑完，避免中途出狀況遺失資料）；`report_detail_screen.dart` 儲存備註時同步寫回
    - `report_history_screen.dart` 改讀 `ReportStore.getAll()`，刪除不再使用的 `frontend/lib/data/fake_reports.dart`
    - 已實機驗證完整流程（開始問答→對話→產生報表→查看歷史紀錄，重開 App 資料還在）
  - **回覆延遲排查**（Step 4 測試後使用者反應「說完話常常要等很久」，甚至會等到忍不住問「還在嗎」）：
    - 一開始想用 `serverContent.inputTranscription`（先開啟 `inputAudioTranscription: {}`）的時間戳記，拆解「使用者講多久」vs「Gemini 判斷+生成花多久」。**結果不可行**：官方文件明講 inputTranscription 不保證跟其他事件的時間順序，實測也真的看到轉錄內容出現在 `tool_call`/`turn_complete` 之後，但使用者其實是在那之前講的話。**已把這個診斷用設定關掉**（順便省掉 Gemini 那邊多跑一份語音轉文字的負擔）
    - 查證 Gemini Live API 官方文件（`https://ai.google.dev/gemini-api/docs/live-api/capabilities`）：`silenceDurationMs` 伺服器內部預設約 800ms、建議範圍 500~800ms。我們原本設的 1750ms 遠超出這個範圍，是延遲感的主因之一，已調整為建議範圍內的 650ms（見 Phase 3 Step 4 記錄）。**尚未實機驗證新數值下思考停頓會不會又太容易被誤判打斷**，之後要留意
    - 順便發現並修正一個真的的 bug：`voice_session_service.dart` 的 WebSocket `onError` 原本完全沒 log；`main.dart` 的 `onDisconnected` 原本只有在「報表已產生、等收尾」的情境才會處理，**連線在報表產生前就意外斷掉時畫面會卡住**（`_isCallActive` 沒重置、沒有任何提示），已修正成不管有沒有待處理的報表都會正確收尾並提示「連線中斷，請重新開始通話」，也補上 WebSocket 錯誤的 log，方便下次真的斷線時排查根因
  - checkpoint：完整跑一次「開始問答→BSRS-5 對話→產生報表→寫入本地→查看歷史紀錄」流程，已實機驗證通過
- [ ] **Phase 5：收尾** ← 接下來從這裡開始
  - [x] 錯誤處理（斷線重連、麥克風權限被拒等邊界情況）
    - 麥克風權限被拒：`voice_session_service.dart` 的 `start()` 一開始就檢查，拒絕會拋例外並顯示「無法開始通話」，有測試涵蓋（`test/widget_test.dart`）
    - 連線意外斷開（報表產生前）：`onDisconnected` 會正確收尾（停止通話、重置畫面）並提示「連線中斷，請重新開始通話」，不會卡住
    - 連線中缺乏回饋：`start()` 改成真的 `await channel.ready`，按鈕會顯示連線中動畫，超過 5 秒還沒連上會提示「後端可能正在喚醒中」（對應 Render 冷啟動）
    - **刻意不做的部分**：真正的「斷線重連接續對話」（session resumption）——Gemini Live 的對話狀態存在 session 裡，斷線後重連只能開全新對話，沒辦法接續訪談進度，除非另外實作 Gemini 的 session resumption 機制，評估後決定先不做，改成乾淨失敗+提示重新開始
    - 已確認 Android（`RECORD_AUDIO`/`INTERNET`）、iOS（`NSMicrophoneUsageDescription`）權限宣告都已在 Phase 1 Step 1 補齊
  - [ ] 實機/多裝置驗收

## 重要提醒

- **金鑰安全**：`backend/.env` 放實際金鑰，`.env.example` 只能放佔位值，`.gitignore` 已排除 `.env`（曾經不小心把金鑰打進 `.env.example`，已修正並確認沒進 git 歷史）
- **Render 免費方案**：閒置會休眠，正式 Demo 前需再評估是否升級或加 keep-alive 腳本
