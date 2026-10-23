import { cleanText, validateEndpoint } from './validation.js';

export const PROVIDERS = Object.freeze({
  ollama: { label: 'Ollama (local)', endpoint: 'http://127.0.0.1:11434', model: 'qwen3:latest', local: true, credential: false },
  lmstudio: { label: 'LM Studio (local)', endpoint: 'http://127.0.0.1:1234/v1', model: 'local-model', local: true, credential: false },
  openai: { label: 'OpenAI Responses', endpoint: 'https://api.openai.com/v1', model: 'gpt-5.4', local: false, credential: true },
  anthropic: { label: 'Anthropic Claude', endpoint: 'https://api.anthropic.com/v1', model: 'claude-sonnet-4-5', local: false, credential: true },
  gemini: { label: 'Google Gemini', endpoint: 'https://generativelanguage.googleapis.com/v1beta', model: 'gemini-2.5-pro', local: false, credential: true },
  compatible: { label: 'OpenAI-compatible', endpoint: 'https://example.invalid/v1', model: 'model-name', local: false, credential: true }
});

function timeoutSignal(milliseconds = 60_000) {
  return AbortSignal.timeout(milliseconds);
}

async function requestJson(url, options, fetchImpl = fetch) {
  const response = await fetchImpl(url, { ...options, signal: timeoutSignal() });
  const raw = await response.text();
  let body;
  try { body = raw ? JSON.parse(raw) : {}; } catch { body = { raw }; }
  if (!response.ok) {
    const detail = body?.error?.message ?? body?.message ?? body?.raw ?? response.statusText;
    throw new Error(`${response.status} ${cleanText(detail, 1_000)}`);
  }
  return body;
}

export function normalizeConfiguration(input) {
  const provider = Object.hasOwn(PROVIDERS, input?.provider) ? input.provider : 'ollama';
  const definition = PROVIDERS[provider];
  return {
    provider,
    endpoint: validateEndpoint(input?.endpoint || definition.endpoint, true),
    model: cleanText(input?.model || definition.model, 200),
    maximumPassages: Math.max(1, Math.min(Number(input?.maximum_passages ?? input?.maximumPassages) || 12, 50)),
    maximumOutputTokens: Math.max(128, Math.min(Number(input?.maximum_output_tokens ?? input?.maximumOutputTokens) || 1200, 32_000)),
    externalTransmissionEnabled: Boolean(input?.external_transmission_enabled ?? input?.externalTransmissionEnabled),
    reasoningEffort: cleanText(input?.reasoning_effort ?? input?.reasoningEffort ?? 'medium', 20),
    local: definition.local,
    requiresCredential: definition.credential
  };
}

function buildPrompt(query, passages) {
  const sources = passages.map((passage, index) =>
    `[S${index + 1}] ${passage.title}, page ${passage.page}\n${passage.passage_text}`).join('\n\n');
  return `You are assisting a researcher. Use only the supplied source passages for factual claims about the literature. Cite them exactly as [S1], [S2], and so on. If the sources are insufficient, say so explicitly. Distinguish source evidence from interpretation.\n\nRESEARCH TASK\n${query}\n\nSOURCE PASSAGES\n${sources || '(No source passages supplied.)'}`;
}

export async function runProvider(rawConfiguration, credential, query, passages, { test = false, fetchImpl = fetch } = {}) {
  const config = normalizeConfiguration(rawConfiguration);
  if (!config.local && !config.externalTransmissionEnabled) {
    throw new Error('External AI transmission is off. Enable it explicitly before sending a request.');
  }
  if (config.requiresCredential && !credential) throw new Error('This provider needs an API key for this session or the secure credential store.');
  const prompt = test
    ? 'Reply with exactly: Research Atlas connection verified.'
    : buildPrompt(cleanText(query, 20_000), passages);
  const maxTokens = test ? 30 : config.maximumOutputTokens;

  if (config.provider === 'ollama') {
    const body = await requestJson(`${config.endpoint}/api/chat`, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ model: config.model, stream: false, messages: [{ role: 'user', content: prompt }],
        options: { num_predict: maxTokens } })
    }, fetchImpl);
    return cleanText(body?.message?.content ?? '', 2_000_000);
  }

  if (config.provider === 'openai') {
    const body = await requestJson(`${config.endpoint}/responses`, {
      method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${credential}` },
      body: JSON.stringify({ model: config.model, input: prompt, max_output_tokens: maxTokens,
        reasoning: { effort: config.reasoningEffort } })
    }, fetchImpl);
    return cleanText(body?.output_text ?? body?.output?.flatMap((item) => item.content ?? [])
      .map((item) => item.text ?? '').join('\n') ?? '', 2_000_000);
  }

  if (config.provider === 'anthropic') {
    const body = await requestJson(`${config.endpoint}/messages`, {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-api-key': credential, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({ model: config.model, max_tokens: maxTokens, messages: [{ role: 'user', content: prompt }] })
    }, fetchImpl);
    return cleanText((body?.content ?? []).map((part) => part.text ?? '').join('\n'), 2_000_000);
  }

  if (config.provider === 'gemini') {
    const url = `${config.endpoint}/models/${encodeURIComponent(config.model)}:generateContent`;
    const body = await requestJson(url, {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-goog-api-key': credential },
      body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { maxOutputTokens: maxTokens } })
    }, fetchImpl);
    return cleanText((body?.candidates?.[0]?.content?.parts ?? []).map((part) => part.text ?? '').join('\n'), 2_000_000);
  }

  const body = await requestJson(`${config.endpoint}/chat/completions`, {
    method: 'POST', headers: { 'content-type': 'application/json', ...(credential ? { authorization: `Bearer ${credential}` } : {}) },
    body: JSON.stringify({ model: config.model, max_tokens: maxTokens, messages: [{ role: 'user', content: prompt }] })
  }, fetchImpl);
  return cleanText(body?.choices?.[0]?.message?.content ?? '', 2_000_000);
}
