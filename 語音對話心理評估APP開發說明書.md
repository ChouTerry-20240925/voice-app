# **📱 語音對話心理評估 APP 開發說明書**

## **壹、 專案概述**

本 APP 旨在提供一個全語音互動的心理健康引導介面。透過虛擬人物（Avatar）與使用者進行即時語音對談，過程中不需輸入任何文字。系統內建「訪談模式（以 BSRS-5 量表為例）」與「專業問答模式」，並能在對話結束後自動結算分數、生成標準化報表，提供使用者檢閱及添加個人備註。

## **貳、 系統架構設計**

為確保 API 金鑰安全並維持語音串流的低延遲，採用 **Frontend \+ Proxy Backend** 架構：

* **前端 (Client)：Flutter**  
  * 負責錄音（Audio Input）、播放音訊（Audio Output）、呈現虛擬人物動畫與介面互動。  
  * 將使用者的錄音（PCM 格式）透過 WebSocket 傳送至後端。  
* **後端 (Proxy)：Render (建議使用 Node.js / Python)**  
  * 作為中繼站（WebSocket Proxy），負責將 Flutter 傳來的音訊轉發給 Gemini API，並將 Gemini 回傳的音訊與工具呼叫（Tool Call）轉發回前端。  
  * 隱藏並管理 Gemini API Key（設置於 Render 環境變數）。  
* **AI 核心：Gemini 2.0 Flash (Multimodal Live API)**  
  * 處理語音轉文字、語意理解、情緒同理、對話推進與結構化報表生成。

## **參、 介面與互動設計 (UI/UX)**

### **1\. 首頁介面 (主畫面)**

* **視覺中心 (Center)**：放置 **虛擬人物 (Avatar)**，建議採用 Lottie 套件實現。當使用者說話時呈現「傾聽」動畫，模型回覆時呈現「說話」動畫。  
* **右側控制列 (Right Column)**：垂直排列三個核心功能按鈕：  
  1. 訪談模式：點擊後載入 BSRS-5 引導設定檔。  
  2. 專業問答模式：點擊後載入自由諮詢設定檔（如心理衛生衛教）。  
  3. 報表輸出（位於右下角）：點擊後跳轉至「歷史報表與備註」頁面。  
* **底部操作區 (Bottom)**：  
  * 開始問答 大型按鈕。點擊後系統會連接 WebSocket 並啟動麥克風，虛擬人物開始以語音開場。  
  * 通話進行中，該按鈕自動切換為 結束通話。

### **2\. 歷史報表與備註頁面**

* **清單視圖 (List View)**：條列過去完成的測驗紀錄（依時間排序）。  
* **報表詳情區**：點開單筆紀錄後，呈現 Gemini 產出的結構化量表。  
* **備註功能**：在每筆評估項目的旁邊（或下方），提供一個文字輸入框 \[新增備註\]，讓使用者可以打字記錄當時的特殊狀況（例如：「今天因為專案截止日所以特別焦慮」），並儲存於設備本地端。

## **肆、 核心模組與技術實作**

### **模組一：全語音即時雙向通訊**

* **Flutter 套件**：使用 record 套件擷取麥克風音訊（16kHz/24kHz PCM 格式），使用 audioplayers 或 just\_audio 播放回傳的音訊串流。使用 web\_socket\_channel 建立連線。  
* **通訊協定**：建立雙向 WebSocket。  
  * **上行**：Flutter \-\> Render \-\> Gemini (包含 realtime\_input 音訊塊)  
  * **下行**：Gemini \-\> Render \-\> Flutter (接收 server\_content 中的音訊塊播放)

### **模組二：AI 對話邏輯與 BSRS-5 訪談**

不需在 APP 端撰寫複雜的問答題庫邏輯，完全依賴 Gemini 的 **System Instructions** 與 **Tool Calling (Function Calling)** 進行控制。

**訪談模式 (BSRS-5) 的系統提示詞 (System Prompt) 核心要求：**

> 你是一位溫暖的心理健康語音助理。請依序詢問使用者 BSRS-5 的 6 個問題：1.睡眠困難 2.焦慮不安 3.易怒 4.低落 5.自信心低落 6.負面念頭。

> 規則：

1. 每次只能用口語問「一題」，等待回覆。  
2. 收到回覆後，先溫柔同理，再問下一題。  
3. 對話結束時，請呼叫工具 generate\_report 匯出結果，並用語音道別。

### **模組三：報表解析與本地儲存**

* **觸發機制**：當模型判定 6 題皆詢問完畢，會透過 WebSocket 下發一個 tool\_call 訊號（不含語音）。  
* **前端處理**：Flutter 解析到 tool\_call 名稱為 generate\_report 時，立刻自動斷開 WebSocket，停止錄音，並將收到的 JSON 資料渲染至報表頁面。  
* **本地資料庫**：使用 Flutter 的 sqflite 或 hive 套件，將每次的報表 JSON 與使用者後續填寫的「備註」關聯儲存。

## **伍、 資料結構與格式規範**

### **1\. 報表工具宣告 (Tool Schema)**

在初始化連線時，需一併傳送此結構給 Gemini：

{  
  "name": "generate\_report",  
  "description": "測驗完成後，輸出結構化 BSRS-5 報表",  
  "parameters": {  
    "type": "OBJECT",  
    "properties": {  
      "report\_content": {  
        "type": "STRING",  
        "description": "依照規定格式排版的完整量表內容"  
      },  
      "total\_score": { "type": "INTEGER" },  
      "result\_analysis": { "type": "STRING" }  
    }  
  }  
}

### **2\. 最終報表輸出格式標準**

Flutter 前端接收到的 report\_content 必須嚴格遵循以下字串格式，以便直接顯示於介面上：

問題一 睡眠困難 回答:非常難入睡，一直做夢 \=\>分數：3  
問題二 焦慮不安 回答:最近工作壓力大，常常心悸 \=\>分數：2  
問題三 易怒情緒 回答:還好，沒有特別生氣 \=\>分數：0  
問題四 低落沮喪 回答:覺得提不起勁 \=\>分數：1  
問題五 自信心低落 回答:覺得自己表現很差 \=\>分數：2  
問題六 負面念頭 回答:完全沒有 \=\>分數：0

量表分數：8 \=\> 結果  
評估結果：中度情緒困擾。建議您適度安排放鬆活動，若持續不適可考慮尋求專業諮詢。

## **陸、 開發階段與排程規劃**

* **Phase 1: 環境與介面建置 (前端)**  
  * 完成 Flutter 專案初始化。  
  * 實作主畫面（Avatar、右側三按鈕、底部開始按鈕）。  
  * 實作報表歷史清單與備註文字框介面。  
* **Phase 2: 伺服器與中繼站建置 (後端)**  
  * 於 Render 建立 Node.js 專案，撰寫 WebSocket Proxy 程式。  
  * 設定 Gemini API Key 環境變數，確保 Flutter 可成功連線至 Render。  
* **Phase 3: 語音串流與 API 串接**  
  * 實作 Flutter 麥克風音訊捕捉與 PCM/Base64 轉換。  
  * 串接雙向 WebSocket 音訊播放，測試語音延遲與打斷（Barge-in）機制。  
* **Phase 4: Prompt 最佳化與資料持久化**  
  * 精煉 BSRS-5 訪談與專業問答的 System Prompt。  
  * 實作接收 generate\_report 事件，並將報表資料寫入本地端資料庫。

## **柒、 部署與特別注意事項**

1. **Render 部署設定**：  
   * **機房選擇 (Region)**：強烈建議選擇 **Singapore (新加坡)** 節點，這是確保台灣使用者語音延遲最低的關鍵。  
   * **冷啟動問題**：若使用 Render 免費方案 (Free Tier)，閒置超過 15 分鐘伺服器會休眠。首次點擊「開始問答」可能會有 30\~50 秒的延遲。若作為正式 Demo 展示，建議展示期間升級為付費方案或撰寫 Keep-alive 腳本定時喚醒。  
2. **Flutter 權限要求**：  
   * **iOS**：必須在 Info.plist 加入 NSMicrophoneUsageDescription 麥克風使用權限說明。  
   * **Android**：必須在 AndroidManifest.xml 加入 RECORD\_AUDIO 與 INTERNET 權限。  
3. **語音活動偵測 (VAD)**：  
   * 心理諮商對談中常有停頓與沉默。建議前端的靜音偵測不要太過敏感，留給使用者至少 1.5 \~ 2 秒的思考時間，避免過快截斷使用者的發言。