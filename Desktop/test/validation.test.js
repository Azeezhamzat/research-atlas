import test from 'node:test';
import assert from 'node:assert/strict';
import { safeFtsQuery, validateEndpoint, requireResource } from '../src/validation.js';

test('FTS input becomes a bounded non-executable query', () => {
  assert.equal(safeFtsQuery('"collective intelligence" bias'), '"collective intelligence" AND "bias"*');
  assert.equal(safeFtsQuery('  '), '');
  assert.doesNotMatch(safeFtsQuery('bias OR * DROP TABLE'), /;/);
});

test('only HTTPS and loopback HTTP endpoints are accepted', () => {
  assert.equal(validateEndpoint('https://api.example.test/v1/'), 'https://api.example.test/v1');
  assert.equal(validateEndpoint('http://127.0.0.1:11434/'), 'http://127.0.0.1:11434');
  assert.throws(() => validateEndpoint('http://example.test/v1'), /HTTPS/);
  assert.throws(() => validateEndpoint('file:///etc/passwd'), /HTTPS/);
  assert.throws(() => validateEndpoint('https://user:pass@example.test'), /must not/);
});

test('resource access is allow-listed', () => {
  assert.equal(requireResource('questions').table, 'research_questions');
  assert.throws(() => requireResource('sqlite_master'), /Unsupported/);
});
