import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeConfiguration, runProvider } from '../src/ai-provider.js';

test('hosted providers remain disabled without explicit transmission consent', async () => {
  await assert.rejects(() => runProvider({
    provider: 'openai', endpoint: 'https://api.openai.com/v1', model: 'test',
    externalTransmissionEnabled: false
  }, 'secret', 'question', []), /transmission is off/);
});

test('local Ollama adapter sends a bounded request to loopback', async () => {
  const fetchImpl = async (url, options) => {
    assert.equal(url, 'http://127.0.0.1:11434/api/chat');
    const parsed = JSON.parse(options.body);
    assert.equal(parsed.model, 'qwen-test');
    assert.match(parsed.messages[0].content, /\[S1\]/);
    return new Response(JSON.stringify({ message: { content: 'Grounded local answer [S1].' } }), {
      status: 200, headers: { 'content-type': 'application/json' }
    });
  };
  const result = await runProvider({
    provider: 'ollama', endpoint: 'http://127.0.0.1:11434', model: 'qwen-test',
    maximumOutputTokens: 500
  }, '', 'What follows?', [{ title: 'Paper', page: 2, passage_text: 'Evidence', id: 'p:2', literature_id: 'p' }], { fetchImpl });
  assert.equal(result, 'Grounded local answer [S1].');
});

test('provider configuration rejects remote cleartext endpoints', () => {
  assert.throws(() => normalizeConfiguration({ provider: 'compatible', endpoint: 'http://remote.example/v1' }), /HTTPS/);
});
