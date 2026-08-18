# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

語音對話心理評估 APP：全語音互動的心理健康引導介面，虛擬人物（Avatar）與使用者即時語音對談。內建「訪談模式」（BSRS-5 量表）與「專業問答模式」，對話結束後由 Gemini 產出結構化報表供使用者檢閱、加備註。

Full spec: `語音對話心理評估APP開發說明書.md`. Current build status and next steps: `TODO.md` — **read this first**, it tracks what phase the project is in and exactly which step to pick up next.

## Architecture

Two-part system, `frontend/` (Flutter) and `backend/` (Node.js), communicating over WebSocket. The backend exists solely to keep the Gemini API key off the client and to proxy the Gemini Live session — it holds no other business logic.

```
Flutter (record → PCM/Base64) --WebSocket--> Node.js proxy --Gemini Live API (@google/genai)--> Gemini 2.5 Flash
Flutter (audio playback)      <--WebSocket-- Node.js proxy <--audio / tool_call-------------------
```

- `backend/src/server.js` — HTTP server (`/health`) + `WebSocketServer`. On each client connection, opens one Gemini Live session via `bridgeClientToGemini`. Client messages of `{"type":"audio","data":"<base64>","mimeType":"audio/pcm;rate=16000"}` are forwarded to Gemini via `sendRealtimeInput`. Closing the client socket closes the Gemini session (1:1 lifecycle).
- `backend/src/geminiLive.js` — Wraps `ai.live.connect()` (model: `gemini-2.5-flash-native-audio-latest` — see `MODEL_NAME`; other model IDs from the spec/SDK docs have been tried and don't work with the current key). `forwardGeminiMessageToClient` translates Gemini's `serverContent`/`toolCall` messages into the client-facing protocol:
  - `{"type":"audio","data":...,"mimeType":...}` — audio chunk out
  - `{"type":"turn_complete"}`
  - `{"type":"tool_call","functionCalls":[...]}`
  - `systemInstruction` and `tools` (the `generate_report` function schema from the spec, §伍) are **not yet wired into `config`** — this is Phase 4 work, currently a placeholder.
- `frontend/lib/main.dart` — Home screen: Avatar placeholder, three mode buttons (訪談模式 / 專業問答模式 / 報表輸出), start/end-call button. `_selectInterviewMode`/`_selectQaMode` are still no-ops (Phase 4 will make them choose which config to send on connect).
- `frontend/lib/screens/report_history_screen.dart`, `report_detail_screen.dart` — history list + detail/notes UI, currently driven by fake data (`frontend/lib/data/fake_reports.dart`) and an in-memory `ReportRecord.note` (`frontend/lib/models/report_record.dart`). Nothing is persisted yet — Phase 4 replaces this with `hive`.
- No audio capture/playback, avatar animation, or persistence code exists yet (`record`, `flutter_sound`, `hive` are planned but not installed — see TODO.md Phase 3/4).

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
