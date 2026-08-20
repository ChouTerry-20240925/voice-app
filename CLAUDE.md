# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

語音對話心理評估 APP：全語音互動的心理健康引導介面，虛擬人物（Avatar）與使用者即時語音對談。內建「訪談模式」（BSRS-5 量表）與「專業問答模式」，對話結束後由 Gemini 產出結構化報表供使用者檢閱、加備註。

## Architecture

Two-part system, `frontend/` (Flutter) and `backend/` (Node.js), communicating over WebSocket. The backend exists solely to keep the Gemini API key off the client and to proxy the Gemini Live session — it holds no other business logic.

```
Flutter (hidden WebView: getUserMedia → PCM/Base64) --WebSocket--> Node.js proxy --Gemini Live API (@google/genai)--> Gemini 2.5 Flash
Flutter (hidden WebView: Web Audio playback)        <--WebSocket-- Node.js proxy <--audio / tool_call-------------------
```

- `backend/src/server.js` — HTTP server (`/health`) + `WebSocketServer`. On each client connection, opens one Gemini Live session via `bridgeClientToGemini`. Client messages of `{"type":"audio","data":"<base64>","mimeType":"audio/pcm;rate=16000"}` are forwarded to Gemini via `sendRealtimeInput`. Closing the client socket closes the Gemini session (1:1 lifecycle).
- `backend/src/geminiLive.js` — Wraps `ai.live.connect()` (model: `gemini-3.1-flash-live-preview` — see `MODEL_NAME`). Config differs by `mode`: 訪談模式 uses `INTERVIEW_SYSTEM_PROMPT` + the `generate_report` tool; 專業問答模式 uses `QA_SYSTEM_PROMPT` + a `search_knowledge_base` tool that queries the 台大醫院心臟移植術後護理指引 RAG knowledge base (`backend/src/ragService.js` — see `doc/RAG串接.md`) and feeds the result back via `sendToolResponse` without ever reaching the client. `forwardGeminiMessageToClient` translates Gemini's `serverContent`/`toolCall` messages into the client-facing protocol:
  - `{"type":"audio","data":...,"mimeType":...}` — audio chunk out
  - `{"type":"interrupted"}` — barge-in
  - `{"type":"turn_complete"}`
  - `{"type":"tool_call","functionCalls":[...]}` — only for `generate_report`; `search_knowledge_base` calls stay server-side.
- `frontend/lib/main.dart` — Home screen: Avatar (idle/listening/thinking/speaking states driven by call events and a local mic-amplitude heuristic, see `webview_voice_bridge.dart`), 訪談模式／專業問答模式 mode buttons (`_selectInterviewMode`/`_selectQaMode` set `_selectedMode`, sent to the backend as `mode` on connect), 報表輸出 button, start/end-call button. Once `generate_report` fires and the model's closing remark finishes playing, saves a `ReportRecord` via `ReportStore` and opens `ReportDetailScreen`.
- `frontend/lib/screens/report_history_screen.dart`, `report_detail_screen.dart` — history list + detail/notes UI, backed by `frontend/lib/services/report_store.dart` (Hive-persisted `ReportRecord`s — see `frontend/lib/models/report_record.dart`); notes are saved back to the same box on edit.
- `frontend/lib/services/webview_voice_bridge.dart` + `frontend/assets/voice_webview/index.html` — mic capture, playback, and the WebSocket link to the backend all run inside a hidden `flutter_inappwebview` `InAppWebView`, not via native Flutter audio plugins. Reason: `record` (mic) + `flutter_sound` (speaker) each opened their own native audio session, so the OS's echo canceller had no reference signal for what was being played — speaker output leaked into the mic and Gemini's VAD mistook it for the user barging in, causing repeated self-interruption. A browser's `getUserMedia({echoCancellation:true})` and Web Audio playback share one pipeline, so the reference signal is there for free. `record` is still a dependency, but only for `AudioRecorder().hasPermission()`'s side effect of triggering Android's OS-level `RECORD_AUDIO` runtime permission dialog — `InAppWebView.onPermissionRequest` only grants the in-page JS permission, not the OS one. Android also needs `MODIFY_AUDIO_SETTINGS` in `AndroidManifest.xml` for Chromium to select a recording device.

### Report format contract

The `generate_report` tool result must produce `report_content` as fixed-format lines like:
```
問題一 睡眠困難 回答:<使用者回答> =>分數：<0-4>
...
量表分數：<total> => 結果
評估結果：<result_analysis>
```
`ReportRecord` (`frontend/lib/models/report_record.dart`) mirrors this: `reportContent` (raw formatted string), `totalScore`, `resultAnalysis`, plus a locally-added `note`. Keep any prompt/schema changes and this model in sync.

## Commands

### Backend (`backend/`)
```
npm install         # install deps
npm start            # node src/server.js — reads GEMINI_API_KEY, PORT from .env
```
No lint/test scripts are configured yet. Copy `.env.example` to `.env` and set `GEMINI_API_KEY` before running — never put a real key in `.env.example` (this has happened before and was caught before hitting git history).

### Frontend (`frontend/`)
```
flutter pub get                 # install deps
flutter run                     # run on connected device/emulator
flutter analyze                 # static analysis (analysis_options.yaml: flutter_lints)
flutter test                    # run tests (currently just test/widget_test.dart)
```

## Deployment

- Backend deploys to Render (Singapore region, free tier) at `voice-bsrs-backend.onrender.com`. Free tier sleeps after ~15 min idle; first request after sleep takes ~30-50s.
- `GEMINI_API_KEY` is set directly in Render's environment variables.
