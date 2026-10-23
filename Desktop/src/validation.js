export const RESOURCE_DEFINITIONS = Object.freeze({
  projects: {
    table: 'research_projects', title: 'title', order: 'modified_at DESC',
    fields: ['title', 'summary'], required: ['title'], defaults: { summary: '' }
  },
  questions: {
    table: 'research_questions', title: 'question', order: 'modified_at DESC',
    fields: ['project_id', 'parent_question_id', 'question', 'notes', 'status', 'objectives',
      'theoretical_interests', 'conceptual_definitions', 'unresolved_disagreements',
      'potential_hypotheses', 'methodological_considerations'],
    required: ['project_id', 'question'],
    defaults: { notes: '', status: 'Developing', objectives: '', theoretical_interests: '',
      conceptual_definitions: '', unresolved_disagreements: '', potential_hypotheses: '',
      methodological_considerations: '', parent_question_id: null }
  },
  arguments: {
    table: 'research_arguments', title: 'proposition', order: 'modified_at DESC',
    fields: ['question_id', 'proposition', 'qualification', 'status'], required: ['proposition'],
    defaults: { question_id: null, qualification: '', status: 'Developing' }
  },
  concepts: {
    table: 'research_concepts', title: 'name', order: 'modified_at DESC',
    fields: ['name', 'definition', 'notes', 'verification', 'origin'], required: ['name'],
    defaults: { definition: '', notes: '', verification: 'Unverified', origin: 'Researcher' }
  },
  claims: {
    table: 'research_claims', title: 'claim_text', order: 'modified_at DESC',
    fields: ['claim_text', 'category', 'literature_id', 'source_passage_id', 'page',
      'quoted_source_text', 'author_terminology', 'methodological_context', 'evidence_type',
      'related_constructs_json', 'study_context', 'extraction_method', 'model_identifier',
      'prompt_version', 'verification', 'user_notes'],
    required: ['claim_text'],
    defaults: { category: 'Interpretation', literature_id: null, source_passage_id: null, page: null,
      quoted_source_text: '', author_terminology: '', methodological_context: '', evidence_type: '',
      related_constructs_json: '[]', study_context: '', extraction_method: 'Manual',
      model_identifier: null, prompt_version: null, verification: 'Unverified', user_notes: '' }
  },
  ideas: {
    table: 'research_ideas', title: 'title', order: 'modified_at DESC',
    fields: ['project_id', 'question_id', 'title', 'body', 'status', 'assumptions',
      'alternative_explanations', 'evidence_needed', 'investigation_notes'], required: ['title'],
    defaults: { project_id: null, question_id: null, body: '', status: 'Seed', assumptions: '',
      alternative_explanations: '', evidence_needed: '', investigation_notes: '' }
  },
  contradictions: {
    table: 'contradiction_cases', title: 'title', order: 'modified_at DESC',
    fields: ['question_id', 'title', 'summary', 'status', 'resolution_notes'], required: ['title'],
    defaults: { question_id: null, summary: '', status: 'Open', resolution_notes: '' }
  },
  writing: {
    table: 'writing_documents', title: 'title', order: 'modified_at DESC',
    fields: ['project_id', 'question_id', 'title', 'purpose', 'status', 'notes'], required: ['title'],
    defaults: { project_id: null, question_id: null, purpose: '', status: 'Outline', notes: '' }
  }
});

export function requireResource(name) {
  const definition = RESOURCE_DEFINITIONS[name];
  if (!definition) throw new Error(`Unsupported workspace: ${String(name)}`);
  return definition;
}

export function cleanText(value, max = 100_000) {
  if (value === null || value === undefined) return '';
  return String(value).replaceAll('\u0000', '').slice(0, max).trim();
}

export function optionalText(value, max = 10_000) {
  const cleaned = cleanText(value, max);
  return cleaned || null;
}

export function integerOrNull(value, min = 0, max = 9999) {
  if (value === '' || value === null || value === undefined) return null;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) return null;
  return parsed;
}

export function assertId(value, label = 'record') {
  if (typeof value !== 'string' || !/^[0-9a-f-]{36}$/i.test(value)) {
    throw new Error(`Invalid ${label} identifier.`);
  }
  return value;
}

export function safeFtsQuery(input) {
  const source = cleanText(input, 500);
  if (!source) return '';
  const phrases = [...source.matchAll(/["“”]([^"“”]+)["“”]/g)]
    .map((match) => match[1].replace(/["*:^(){}\[\]]/g, ' ').trim())
    .filter(Boolean)
    .map((phrase) => `"${phrase}"`);
  const remaining = source.replace(/["“”][^"“”]+["“”]/g, ' ');
  const words = remaining
    .split(/[^\p{L}\p{N}_-]+/u)
    .map((word) => word.replace(/[-]+/g, ' ').trim())
    .filter(Boolean)
    .slice(0, 12)
    .map((word) => `"${word}"*`);
  return [...phrases, ...words].join(' AND ');
}

export function isLoopbackEndpoint(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'http:' && ['127.0.0.1', 'localhost', '::1'].includes(url.hostname);
  } catch {
    return false;
  }
}

export function validateEndpoint(value, allowLoopback = true) {
  const cleaned = cleanText(value, 2_000);
  let url;
  try { url = new URL(cleaned); } catch { throw new Error('Enter a valid API endpoint URL.'); }
  if (url.username || url.password) throw new Error('Credentials must not be embedded in the endpoint URL.');
  if (url.protocol === 'https:') return url.toString().replace(/\/$/, '');
  if (allowLoopback && isLoopbackEndpoint(url.toString())) return url.toString().replace(/\/$/, '');
  throw new Error('Hosted providers require HTTPS. HTTP is allowed only for a local loopback server.');
}
