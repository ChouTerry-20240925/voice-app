# 語音對話心理評估 APP — 建置待辦事項

> 最後更新：2026-08-18。接續開發前請先讀這份文件。

## 已確認的技術選型

| 項目 | 選擇 |
|---|---|
| 前端 | Flutter，專案名稱 `voice_bsrs_app`，App ID `com.example.voice_bsrs_app` |
| 後端 | Node.js（`backend/`），部署於 Render Free Tier（Singapore） |
| 音訊播放 | `flutter_sound`（尚未安裝，Phase 3 要用） |
| 錄音 | `record` 套件（尚未安裝，Phase 3 要用） |
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
- [ ] **Phase 3：語音串流整合** ← 接下來從這裡開始
  - [ ] Step 1：Flutter 端用 `record` 套件擷取 16kHz/24kHz PCM，轉 Base64，透過 WebSocket 送到 backend（協定格式：`{"type":"audio","data":"<base64>","mimeType":"audio/pcm;rate=16000"}`，backend 已經支援接收這個格式）
  - [ ] Step 2：Flutter 端用 `flutter_sound` 串流播放 backend 轉發回來的音訊（backend 送出格式：`{"type":"audio","data":"<base64>","mimeType":"..."}`）
  - [ ] Step 3：Avatar 動畫狀態機（傾聽/說話狀態切換）
  - [ ] Step 4：測試語音延遲、Barge-in（打斷）機制、VAD 靜音容忍度（1.5~2 秒不要太敏感）
  - checkpoint：實機測試一次完整語音來回
- [ ] **Phase 4：Prompt 設計與報表持久化**
  - [ ] Step 1：撰寫 BSRS-5 訪談模式 System Prompt + `generate_report` tool schema（需在 `ai.live.connect()` 的 `config` 加上 `systemInstruction` 與 `tools`，目前 `backend/src/geminiLive.js` 尚未設定這兩項，是佔位骨架）
  - [ ] Step 2：撰寫專業問答模式 System Prompt
  - [ ] Step 3：前端接收 `tool_call`（backend 已會轉發 `{"type":"tool_call","functionCalls":[...]}`）後自動斷線、解析 `report_content`/`total_score`/`result_analysis` 並渲染到報表頁
  - [ ] Step 4：`hive` 串接，把報表 JSON + 備註改成真正寫入本地資料庫（目前 `frontend/lib/screens/report_detail_screen.dart` 的備註只存在 State 記憶體裡，重開 App 會消失）
  - checkpoint：完整跑一次「開始問答→BSRS-5 對話→產生報表→寫入本地→查看歷史紀錄」流程
- [ ] **Phase 5：收尾**
  - [ ] 錯誤處理（斷線重連、麥克風權限被拒等邊界情況）
  - [ ] 實機/多裝置驗收

## 重要提醒

- **金鑰安全**：`backend/.env` 放實際金鑰，`.env.example` 只能放佔位值，`.gitignore` 已排除 `.env`（曾經不小心把金鑰打進 `.env.example`，已修正並確認沒進 git 歷史）
- **Render 免費方案**：閒置會休眠，正式 Demo 前需再評估是否升級或加 keep-alive 腳本
- **右側「訪談模式」「專業問答模式」按鈕**目前是空邏輯（no-op），要等 Phase 4 System Prompt 完成後才會真正決定連線時要送哪一種設定
