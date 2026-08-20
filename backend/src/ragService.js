/**
 * RAG 查詢服務模組（方案 A：OpenAI text-embedding-3-small，1536 維度）
 * 職責：接收查詢字串 → 透過 OpenAI 計算 1536 維向量 → 查 Supabase RPC (match_ntuh_documents) → 回傳指引段落
 */
const { createClient } = require('@supabase/supabase-js');
const { OpenAI } = require('openai');

const EMBEDDING_MODEL = 'text-embedding-3-small';
const MATCH_THRESHOLD = 0.25;
const MATCH_COUNT = 3;
const MAX_CONTEXT_CHARS = 1500;

let _supabase = null;
let _openai = null;

function getSupabase() {
  if (!_supabase) {
    const url = process.env.SUPABASE_URL;
    const key = process.env.SUPABASE_ANON_KEY;
    if (!url || !key) throw new Error('SUPABASE_URL 或 SUPABASE_ANON_KEY 未設定');
    _supabase = createClient(url, key);
  }
  return _supabase;
}

function getOpenAI() {
  if (!_openai) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) throw new Error('OPENAI_API_KEY 未設定');
    _openai = new OpenAI({ apiKey });
  }
  return _openai;
}

async function embedQuery(query) {
  const openai = getOpenAI();
  const response = await openai.embeddings.create({
    model: EMBEDDING_MODEL,
    input: query,
  });
  return response.data[0].embedding;
}

/**
 * 查詢 NTUH 護理指引資料庫，回傳整理後的參考文字
 * @param {string} query 使用者問題或搜尋關鍵字
 * @returns {Promise<{ context: string, found: boolean }>}
 */
async function searchKnowledgeBase(query) {
  try {
    const supabase = getSupabase();
    const embedding = await embedQuery(query);

    const { data, error } = await supabase.rpc('match_ntuh_documents', {
      query_embedding: embedding,
      match_threshold: MATCH_THRESHOLD,
      match_count: MATCH_COUNT,
    });

    if (error) {
      console.error('[RAG] Supabase 查詢錯誤：', error.message);
      return { context: '', found: false };
    }

    if (!data || data.length === 0) {
      console.log(`[RAG] 未找到相關指引 (query: "${query}")`);
      return { context: '', found: false };
    }

    let context = '';
    for (let i = 0; i < data.length; i++) {
      const row = data[i];
      const snippet = `【參考條目 ${i + 1}】(章節: ${row.section_title})\n${row.content.trim()}`;
      if (context.length + snippet.length > MAX_CONTEXT_CHARS) break;
      context += snippet + '\n\n';
    }

    console.log(
      `[RAG] 命中 ${data.length} 個章節，相似度:`,
      data.map((r) => r.similarity.toFixed(3)).join(', ')
    );

    return { context: context.trim(), found: true };
  } catch (err) {
    console.error('[RAG] 查詢發生例外錯誤：', err.message);
    return { context: '', found: false };
  }
}

module.exports = { searchKnowledgeBase };
