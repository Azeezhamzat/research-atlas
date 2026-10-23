const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

const navigation = [
  { group: 'Start', items: [
    ['home', '⌂', 'Research Home'], ['learning', '◇', 'Learning Center']
  ] },
  { group: 'Sources and reading', items: [
    ['library', '▥', 'Literature Library'], ['reading', '▤', 'Reading Desk'], ['search', '⌕', 'Global Search']
  ] },
  { group: 'Research reasoning', items: [
    ['questions', '◌', 'Research Questions'], ['evidence', '▦', 'Evidence Explorer'],
    ['arguments', '⌁', 'Argument Workspace'], ['atlas', '⌘', 'Knowledge Atlas'],
    ['ideas', '✦', 'Idea Laboratory'], ['contradictions', '⇄', 'Contradictions'],
    ['bias', '◈', 'Bias Auditor'], ['history', '◷', 'Intellectual History']
  ] },
  { group: 'AI and synthesis', items: [
    ['assistant', '✣', 'Research Assistant'], ['room', '◉', 'Argument Room'],
    ['collective', '◎', 'Collective Intelligence'], ['writing', '▱', 'Research Writing']
  ] },
  { group: 'System', items: [['integrations', '⚙', 'Integrations']] }
];

const titles = Object.fromEntries(navigation.flatMap((group) => group.items.map(([key, , label]) => [key, label])));
const resourcePages = {
  questions: {
    resource: 'questions', noun: 'question', intro: 'Develop questions with explicit objectives, concepts, disagreements, hypotheses, and method notes.',
    title: (record) => record.question, body: (record) => record.notes || record.objectives,
    fields: [
      ['question', 'Research question', 'textarea', true], ['status', 'Status', 'select', false, ['Developing', 'Active', 'Answered', 'Archived']],
      ['objectives', 'Objectives', 'textarea'], ['notes', 'Working notes', 'textarea'],
      ['theoretical_interests', 'Theoretical interests', 'textarea'], ['conceptual_definitions', 'Conceptual definitions', 'textarea'],
      ['unresolved_disagreements', 'Unresolved disagreements', 'textarea'], ['potential_hypotheses', 'Potential hypotheses', 'textarea'],
      ['methodological_considerations', 'Methodological considerations', 'textarea']
    ]
  },
  arguments: {
    resource: 'arguments', noun: 'argument', intro: 'Construct qualified propositions and connect each one to inspectable source evidence.',
    title: (record) => record.proposition, body: (record) => record.qualification,
    fields: [['proposition', 'Proposition', 'textarea', true], ['qualification', 'Qualification and boundaries', 'textarea'], ['status', 'Status', 'select', false, ['Developing', 'Qualified', 'Contested', 'Supported', 'Retired']]]
  },
  atlas: {
    resource: 'concepts', noun: 'concept', intro: 'Maintain a bounded vocabulary. Definitions remain distinct from claims and source quotations.',
    title: (record) => record.name, body: (record) => record.definition,
    fields: [['name', 'Concept name', 'text', true], ['definition', 'Working definition', 'textarea'], ['notes', 'Boundary notes', 'textarea'], ['verification', 'Verification', 'select', false, ['Unverified', 'Reviewed', 'Verified']], ['origin', 'Origin', 'select', false, ['Researcher', 'Source', 'AI suggestion']]]
  },
  ideas: {
    resource: 'ideas', noun: 'idea', intro: 'Turn observations into testable ideas while recording assumptions, alternatives, and missing evidence.',
    title: (record) => record.title, body: (record) => record.body,
    fields: [['title', 'Idea title', 'text', true], ['body', 'Idea', 'textarea'], ['status', 'Status', 'select', false, ['Seed', 'Developing', 'Testing', 'Integrated', 'Archived']], ['assumptions', 'Assumptions', 'textarea'], ['alternative_explanations', 'Alternative explanations', 'textarea'], ['evidence_needed', 'Evidence needed', 'textarea'], ['investigation_notes', 'Investigation notes', 'textarea']]
  },
  contradictions: {
    resource: 'contradictions', noun: 'case', intro: 'Compare apparently conflicting findings without assuming that different populations or methods truly contradict.',
    title: (record) => record.title, body: (record) => record.summary,
    fields: [['title', 'Case title', 'text', true], ['summary', 'Apparent conflict', 'textarea'], ['status', 'Status', 'select', false, ['Open', 'Contextual difference', 'Resolved', 'Requires evidence']], ['resolution_notes', 'Resolution or next investigation', 'textarea']]
  },
  writing: {
    resource: 'writing', noun: 'writing document', intro: 'Develop evidence-linked academic writing. Use Grounded AI for bounded critique, not autonomous authorship.',
    title: (record) => record.title, body: (record) => record.purpose || record.notes,
    fields: [['title', 'Document title', 'text', true], ['purpose', 'Purpose and audience', 'textarea'], ['status', 'Status', 'select', false, ['Outline', 'Draft', 'Review', 'Complete']], ['notes', 'Planning notes', 'textarea']]
  }
};

const state = {
  route: 'home', bootstrap: null, library: [], selectedPaperId: null,
  editingResource: null, editingRecord: null, aiPreviewReady: false, aiContext: {}
};

function escapeHTML(value) {
  return String(value ?? '').replace(/[&<>'"]/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
  })[character]);
}

function safeSnippet(value) {
  return escapeHTML(value).replaceAll('&lt;mark&gt;', '<mark>').replaceAll('&lt;/mark&gt;', '</mark>');
}

function formatDate(value) {
  if (!value) return 'Not recorded';
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? escapeHTML(value) : new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' }).format(date);
}

function toast(message, error = false) {
  const item = document.createElement('div');
  item.className = `toast${error ? ' error' : ''}`;
  item.textContent = message;
  $('#toast-region').append(item);
  setTimeout(() => item.remove(), 5_500);
}

async function perform(action, successMessage = '') {
  try {
    const result = await action();
    if (successMessage) toast(successMessage);
    return result;
  } catch (error) {
    toast(error?.message || String(error), true);
    throw error;
  }
}

function setHeading(route) {
  $('#eyebrow').textContent = route === 'integrations' ? 'System and privacy' : route === 'learning' ? 'Guide and onboarding' : 'Research workspace';
  $('#page-title').textContent = titles[route] ?? 'Research Atlas';
  $$('.nav-item').forEach((item) => item.classList.toggle('active', item.dataset.route === route));
}

function buildNavigation() {
  $('#navigation').innerHTML = navigation.map((group) => `
    <p class="nav-group">${escapeHTML(group.group)}</p>
    ${group.items.map(([route, icon, label]) => `<button class="nav-item" data-route="${route}"><span class="nav-icon">${icon}</span><span>${escapeHTML(label)}</span></button>`).join('')}
  `).join('');
  $('#navigation').addEventListener('click', (event) => {
    const button = event.target.closest('[data-route]');
    if (button) go(button.dataset.route);
  });
}

async function go(route) {
  state.route = titles[route] ? route : 'home';
  setHeading(state.route);
  $('#content').innerHTML = '<div class="empty-state"><span>◌</span><p>Loading workspace…</p></div>';
  try {
    if (state.route === 'home') await renderHome();
    else if (state.route === 'library') await renderLibrary();
    else if (state.route === 'reading') await renderReading();
    else if (state.route === 'search' || state.route === 'evidence') await renderSearch(state.route === 'evidence');
    else if (resourcePages[state.route]) await renderResourcePage(state.route);
    else if (state.route === 'assistant') await renderAssistant();
    else if (state.route === 'bias') await renderBias();
    else if (state.route === 'history') await renderHistory();
    else if (state.route === 'room') await renderArgumentRoom();
    else if (state.route === 'collective') await renderCollective();
    else if (state.route === 'integrations') await renderIntegrations();
    else if (state.route === 'learning') renderLearning();
    $('#content').focus({ preventScroll: true });
  } catch (error) {
    $('#content').innerHTML = `<div class="empty-state"><span>!</span><h3>This workspace could not open</h3><p>${escapeHTML(error?.message || error)}</p><button class="secondary" data-action="retry">Try again</button></div>`;
  }
}

async function renderHome() {
  const dashboard = await window.atlas.dashboard();
  const metrics = dashboard.metrics;
  const hasSources = metrics.literature > 0;
  $('#content').innerHTML = `<section class="page">
    <div class="page-heading"><div><h2>Your research, with its reasoning intact</h2><p>Move from source material to questions, evidence, arguments, and writing without losing provenance.</p></div><div class="button-row"><button class="secondary" data-route-link="learning">First-hour guide</button><button class="primary" data-action="add-folder">Add research folder</button></div></div>
    <div class="grid metrics">
      ${[['Literature', metrics.literature], ['Research notes', metrics.notes], ['Questions', metrics.questions], ['Arguments', metrics.arguments], ['Claims', metrics.claims], ['Ideas', metrics.ideas]].map(([label, value]) => `<div class="metric"><span>${label}</span><strong>${value}</strong></div>`).join('')}
    </div>
    ${!hasSources ? `<div class="callout settings-section"><strong>Start with your local folder.</strong> Research Atlas reads PDFs where they already live, builds its own local index, and never reorganises the originals. <button class="primary compact" data-action="add-folder">Choose folder</button></div>` : ''}
    <div class="three-column settings-section">
      <article class="card workflow-card"><span class="step">1</span><h3>Connect sources</h3><p>Index a local PDF folder or select individual documents. Hidden files, packages, and symbolic links are skipped.</p><button class="secondary compact" data-route-link="library">Open library</button></article>
      <article class="card workflow-card"><span class="step">2</span><h3>Frame the investigation</h3><p>Record a question, its objectives, competing explanations, and methodological boundaries.</p><button class="secondary compact" data-route-link="questions">Open questions</button></article>
      <article class="card workflow-card"><span class="step">3</span><h3>Reason with evidence</h3><p>Search exact indexed passages, qualify arguments, and use AI only after inspecting what will be sent.</p><button class="secondary compact" data-route-link="evidence">Explore evidence</button></article>
    </div>
    <div class="two-column">
      <article class="card"><div class="card-header"><h3>Recent recorded activity</h3><button class="secondary compact" data-route-link="history">View history</button></div>
        ${dashboard.recent.length ? `<ul class="activity-list">${dashboard.recent.slice(0, 7).map((item) => `<li><span class="good">●</span><div><strong>${escapeHTML(item.title)}</strong><small>${escapeHTML(item.event_type)} · ${formatDate(item.recorded_at)}</small></div></li>`).join('')}</ul>` : '<p>No research changes have been recorded yet.</p>'}
      </article>
      <article class="card"><div class="card-header"><h3>Integrity queue</h3><span class="pill ${dashboard.integrity.unresolvedEvidence + dashboard.integrity.unavailableSources ? '' : 'success'}">${dashboard.integrity.unresolvedEvidence + dashboard.integrity.unavailableSources ? 'Review needed' : 'Clear'}</span></div>
        <ul class="integrity-list"><li><span class="${dashboard.integrity.unresolvedEvidence ? 'warning' : 'good'}">${dashboard.integrity.unresolvedEvidence ? '△' : '✓'}</span><div><strong>${dashboard.integrity.unresolvedEvidence} evidence link(s) await verification</strong><small>Unverified interpretations remain visibly distinct from checked source support.</small></div></li><li><span class="${dashboard.integrity.unavailableSources ? 'warning' : 'good'}">${dashboard.integrity.unavailableSources ? '△' : '✓'}</span><div><strong>${dashboard.integrity.unavailableSources} source file(s) unavailable</strong><small>Refresh the original folder after moving or renaming PDFs.</small></div></li></ul>
      </article>
    </div>
    <article class="card settings-section"><div class="card-header"><div><h3>Grounded AI is available where the work happens</h3><p>Use the ✦ action above or the contextual button on questions, arguments, evidence, contradiction, bias, and writing pages.</p></div><button class="primary compact" data-action="open-ai">Open AI workspace</button></div><p>Local Ollama and LM Studio requests stay on this computer. Hosted requests show a one-time transmission preview with the exact passages before approval.</p></article>
  </section>`;
}

async function addPDFs() {
  const paths = await window.atlas.library.chooseFiles();
  if (!paths.length) return;
  const result = await perform(() => window.atlas.library.indexFiles(paths));
  toast(`Indexed ${result.imported + result.duplicates} PDF(s); ${result.failures.length} failed.`);
  if (state.route === 'library' || state.route === 'reading' || state.route === 'home') await go(state.route);
}

async function addFolder() {
  const folder = await window.atlas.library.chooseFolder();
  if (!folder) return;
  const result = await perform(() => window.atlas.library.indexFolder(folder));
  toast(`Folder refresh complete: ${result.imported} new, ${result.duplicates} already known, ${result.failures.length} failed.`);
  if (state.route === 'library' || state.route === 'reading' || state.route === 'home') await go(state.route);
}

async function renderLibrary(filters = {}) {
  state.library = await window.atlas.library.list(filters);
  if (!state.selectedPaperId || !state.library.some((item) => item.id === state.selectedPaperId)) state.selectedPaperId = state.library[0]?.id ?? null;
  $('#content').innerHTML = `<section class="page">
    <div class="page-heading"><div><h2>Literature Library</h2><p>Indexed metadata and page text point back to your read-only originals.</p></div><div class="button-row"><button class="secondary" data-action="add-pdfs">Add PDFs</button><button class="primary" data-action="add-folder">Add folder</button></div></div>
    <form id="library-filter" class="toolbar"><input class="search-field" name="query" value="${escapeHTML(filters.query || '')}" placeholder="Filter by title, author, abstract, or tag"><input name="yearFrom" inputmode="numeric" value="${escapeHTML(filters.yearFrom || '')}" placeholder="From year"><input name="yearTo" inputmode="numeric" value="${escapeHTML(filters.yearTo || '')}" placeholder="To year"><select name="availability"><option value="">Any availability</option><option ${filters.availability === 'Available' ? 'selected' : ''}>Available</option><option ${filters.availability === 'Missing' ? 'selected' : ''}>Missing</option></select><button class="secondary">Apply</button></form>
    <div class="split-view">
      <section class="list-pane"><div class="list-pane-header">${state.library.length} paper(s) shown</div><div class="scroll-pane">${state.library.length ? state.library.map((item) => `<button class="record-row ${item.id === state.selectedPaperId ? 'selected' : ''}" data-paper="${item.id}"><strong>${escapeHTML(item.title)}</strong><span>${escapeHTML(item.authors || 'Unknown author')} · ${item.publication_year || 'Year unavailable'} · ${escapeHTML(item.source_availability)}</span></button>`).join('') : '<div class="empty-state compact-empty"><span>▥</span><h3>No indexed papers</h3><p>Add a local folder or individual PDFs to begin.</p></div>'}</div></section>
      <section id="paper-detail" class="detail-pane"></section>
    </div>
  </section>`;
  $('#library-filter').addEventListener('submit', (event) => {
    event.preventDefault();
    renderLibrary(Object.fromEntries(new FormData(event.currentTarget)));
  });
  if (state.selectedPaperId) await renderPaperDetail(state.selectedPaperId);
  else $('#paper-detail').innerHTML = '<div class="empty-state"><span>▥</span><h3>Add your first source</h3><p>Research Atlas indexes a copy of searchable text while leaving the PDF untouched.</p></div>';
}

async function renderPaperDetail(id) {
  state.selectedPaperId = id;
  $$('.record-row').forEach((row) => row.classList.toggle('selected', row.dataset.paper === id));
  const paper = await perform(() => window.atlas.library.paper(id));
  const detail = $('#paper-detail');
  if (!detail) return;
  detail.innerHTML = `<p class="eyebrow">${escapeHTML(paper.item_type)} · ${escapeHTML(paper.source)}</p><h2>${escapeHTML(paper.title)}</h2>
    <div class="metadata"><span class="pill">${escapeHTML(paper.authors || 'Unknown author')}</span><span class="pill">${paper.publication_year || 'Year unavailable'}</span><span class="pill ${paper.source_availability === 'Available' ? 'success' : ''}">${escapeHTML(paper.source_availability)}</span><span class="pill">${paper.passages.length} indexed page(s)</span></div>
    <div class="button-row"><button class="primary compact" data-action="read-paper" data-id="${paper.id}" ${paper.pdf_path ? '' : 'disabled'}>Read PDF</button><button class="secondary compact" data-action="paper-ai" data-id="${paper.id}">Ask with this paper</button></div>
    <div class="section"><h3>Abstract or description</h3><p>${escapeHTML(paper.abstract_text || 'No abstract is recorded. PDF text remains available page by page in search.')}</p></div>
    <div class="section"><h3>Provenance</h3><p><strong>Original:</strong> ${escapeHTML(paper.pdf_path || 'No local file linked')}</p><p><strong>SHA-256:</strong> <code>${escapeHTML(paper.pdf_sha256 || 'Not fingerprinted')}</code></p><p><strong>Last verified:</strong> ${formatDate(paper.pdf_last_verified_at)}</p></div>
    <div class="section"><h3>Linked research</h3><p>${paper.evidence.length} evidence relationship(s) · ${paper.claims.length} structured claim(s)</p></div>`;
}

async function renderReading() {
  const library = await window.atlas.library.list({ availability: 'Available' });
  const selected = library.find((item) => item.id === state.selectedPaperId) ?? library[0];
  if (!selected) {
    $('#content').innerHTML = '<section class="page"><div class="empty-state"><span>▤</span><h3>No available PDF</h3><p>Add a local PDF before opening the Reading Desk.</p><button class="primary" data-action="add-pdfs">Add PDFs</button></div></section>';
    return;
  }
  state.selectedPaperId = selected.id;
  const url = await window.atlas.library.previewUrl(selected.id);
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>${escapeHTML(selected.title)}</h2><p>${escapeHTML(selected.authors || 'Unknown author')} · the original file remains read-only</p></div><div class="button-row"><select id="reading-paper">${library.map((paper) => `<option value="${paper.id}" ${paper.id === selected.id ? 'selected' : ''}>${escapeHTML(paper.title)}</option>`).join('')}</select><button class="primary" data-action="paper-ai" data-id="${selected.id}">Ask with paper</button></div></div><iframe class="paper-preview" title="PDF reading desk" src="${escapeHTML(url)}"></iframe></section>`;
  $('#reading-paper').addEventListener('change', (event) => { state.selectedPaperId = event.target.value; renderReading(); });
}

async function renderResourcePage(route) {
  const config = resourcePages[route];
  const records = await window.atlas.resources.list(config.resource);
  const projects = config.resource === 'questions' ? await window.atlas.resources.list('projects') : [];
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>${escapeHTML(titles[route])}</h2><p>${escapeHTML(config.intro)}</p></div><div class="button-row"><button class="secondary" data-action="context-ai" data-kind="${route}">✦ Use AI here</button><button class="primary" data-action="new-record" data-resource="${config.resource}">New ${escapeHTML(config.noun)}</button></div></div>
    ${config.resource === 'questions' && !projects.length ? '<div class="callout warning-callout">Create a project from Research Home before adding a question.</div>' : ''}
    <div class="record-grid">${records.length ? records.map((record) => `<article class="card record-card"><div><span class="pill">${escapeHTML(record.status || record.verification || record.origin || config.noun)}</span><h3>${escapeHTML(config.title(record))}</h3><p>${escapeHTML(config.body(record) || 'No supporting detail recorded yet.')}</p></div><footer><button class="secondary" data-action="edit-record" data-resource="${config.resource}" data-id="${record.id}">Edit</button><button class="secondary" data-action="record-ai" data-resource="${config.resource}" data-id="${record.id}">✦ Examine</button><button class="secondary danger-text" data-action="delete-record" data-resource="${config.resource}" data-id="${record.id}">Delete</button></footer></article>`).join('') : `<div class="empty-state"><span>◇</span><h3>No ${escapeHTML(config.noun)} records yet</h3><p>Create the first record. It stays local and can be exported with the rest of the workspace.</p><button class="primary" data-action="new-record" data-resource="${config.resource}">Create ${escapeHTML(config.noun)}</button></div>`}</div>
  </section>`;
}

async function renderSearch(evidenceMode = false, initialQuery = '') {
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>${evidenceMode ? 'Evidence Explorer' : 'Global Search'}</h2><p>${evidenceMode ? 'Find exact indexed source passages. Results are retrieval candidates, not automatically verified evidence.' : 'Search literature, page passages, questions, arguments, concepts, claims, ideas, and writing.'}</p></div>${evidenceMode ? '<button class="secondary" data-action="context-ai" data-kind="Evidence review">✦ Analyse retrieved evidence</button>' : ''}</div>
    <form id="search-form" class="toolbar"><input id="search-input" class="search-field" value="${escapeHTML(initialQuery)}" placeholder='Search; use quotation marks for an exact phrase' autofocus><select id="search-type"><option value="">All records</option><option value="literature">Papers</option><option value="passage">PDF passages</option><option value="questions">Questions</option><option value="arguments">Arguments</option><option value="concepts">Concepts</option><option value="claims">Claims</option><option value="ideas">Ideas</option><option value="writing">Writing</option></select><button class="primary">Search</button></form>
    <section id="search-results" class="card"><div class="empty-state compact-empty"><span>⌕</span><h3>Search your research corpus</h3><p>Search runs locally against the Research Atlas full-text index.</p></div></section></section>`;
  $('#search-form').addEventListener('submit', async (event) => {
    event.preventDefault();
    const query = $('#search-input').value;
    const results = await perform(() => window.atlas.search(query, $('#search-type').value));
    $('#search-results').innerHTML = results.length ? results.map((result) => `<article class="result"><span class="pill">${escapeHTML(result.entity_type)}</span><h3>${escapeHTML(result.title)}</h3><p>${safeSnippet(result.excerpt)}</p></article>`).join('') : '<div class="empty-state compact-empty"><span>⌕</span><h3>No matches</h3><p>Try fewer terms, another spelling, or remove the type filter.</p></div>';
  });
  if (initialQuery) $('#search-form').requestSubmit();
}

async function renderAssistant() {
  const history = await window.atlas.ai.history();
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>Research Assistant</h2><p>Ask bounded questions over selected local sources. Every model answer is a reviewable suggestion, never a verified fact.</p></div><button class="primary" data-action="open-ai">New grounded analysis</button></div>
    <div class="callout"><strong>The source contract:</strong> papers use labels such as [S1]. A response that needs evidence not supplied should say the evidence is insufficient. You remain responsible for checking every citation against the source.</div>
    <div class="card settings-section"><div class="card-header"><h3>Analysis history</h3><span class="pill">${history.length} recent</span></div>${history.length ? `<ul class="activity-list">${history.map((item) => `<li><span class="${item.status === 'Failed' ? 'danger-text' : 'good'}">${item.status === 'Failed' ? '!' : '✦'}</span><div><strong>${escapeHTML(item.kind)} · ${escapeHTML(item.model)}</strong><small>${escapeHTML(item.status)} · ${formatDate(item.created_at)}</small><p>${escapeHTML(item.response_text || item.error_message || item.user_query).slice(0, 450)}</p></div></li>`).join('')}</ul>` : '<div class="empty-state compact-empty"><span>✣</span><h3>No AI analyses yet</h3><p>Configure a local or hosted provider, then inspect the exact transmission preview before one request.</p></div>'}</div>
  </section>`;
}

async function renderBias() {
  const argumentsList = await window.atlas.resources.list('arguments');
  const flags = argumentsList.flatMap((argument) => {
    const concerns = [];
    if (!argument.qualification?.trim()) concerns.push(['Missing boundary', 'The proposition has no recorded qualification or scope condition.']);
    if (/\b(always|never|proves?|causes?|all|none)\b/i.test(argument.proposition)) concerns.push(['Overbreadth check', 'Absolute or causal language deserves explicit design and boundary review.']);
    return concerns.map(([kind, detail]) => ({ argument, kind, detail }));
  });
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>Research Bias Auditor</h2><p>A cautious audit of recorded reasoning. These are prompts for reflection, not psychological diagnoses.</p></div><button class="secondary" data-action="context-ai" data-kind="Bias review">✦ Grounded model review</button></div>
    <div class="callout"><strong>Local audit:</strong> checks wording and missing qualifications without transmitting data or claiming that a bias exists.</div>
    <div class="record-grid settings-section">${flags.length ? flags.map((flag) => `<article class="card record-card"><span class="pill">${escapeHTML(flag.kind)}</span><h3>${escapeHTML(flag.argument.proposition)}</h3><p>${escapeHTML(flag.detail)}</p><footer><button class="secondary" data-action="edit-record" data-resource="arguments" data-id="${flag.argument.id}">Review argument</button></footer></article>`).join('') : '<div class="empty-state"><span>◈</span><h3>No local wording flags</h3><p>This does not prove the reasoning is unbiased. Add and verify evidence, consider alternatives, and record qualifications.</p></div>'}</div></section>`;
}

async function renderHistory() {
  const dashboard = await window.atlas.dashboard();
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>Intellectual History</h2><p>A record of changes Research Atlas actually observed. It does not reconstruct unrecorded thinking.</p></div></div><article class="card">${dashboard.recent.length ? `<ul class="activity-list">${dashboard.recent.map((item) => `<li><span class="good">●</span><div><strong>${escapeHTML(item.title)}</strong><small>${escapeHTML(item.entity_type)} · ${escapeHTML(item.event_type)} · ${formatDate(item.recorded_at)}</small><p>${escapeHTML(item.detail || '')}</p></div></li>`).join('')}</ul>` : '<div class="empty-state"><span>◷</span><h3>No recorded changes yet</h3><p>Create or revise a research record to begin an inspectable history.</p></div>'}</article></section>`;
}

async function renderArgumentRoom() {
  const argumentsList = await window.atlas.resources.list('arguments');
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>Argument Room</h2><p>Stress-test one recorded proposition from multiple disclosed perspectives. Model roles are simulations from the same configured model, not independent experts.</p></div><button class="primary" data-action="context-ai" data-kind="Argument critique">Start grounded critique</button></div><div class="three-column"><article class="card"><h3>1. Choose a proposition</h3><p>${argumentsList.length ? `${argumentsList.length} recorded argument(s) are available.` : 'Create an argument before starting a deliberation.'}</p></article><article class="card"><h3>2. Inspect evidence</h3><p>Select the papers to expose to the model. Withheld material is genuinely absent from that turn.</p></article><article class="card"><h3>3. Record your decision</h3><p>Model output remains a suggestion until you accept, reject, or respond to it in your own reasoning.</p></article></div><div class="record-grid settings-section">${argumentsList.map((item) => `<article class="card record-card"><span class="pill">${escapeHTML(item.status)}</span><h3>${escapeHTML(item.proposition)}</h3><p>${escapeHTML(item.qualification || 'No qualification recorded.')}</p><footer><button class="primary" data-action="record-ai" data-resource="arguments" data-id="${item.id}" data-kind="Argument critique">Critique with sources</button></footer></article>`).join('')}</div></section>`;
}

async function renderCollective() {
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>Collective Intelligence Lab</h2><p>Design controlled, sequential role simulations over the same inspectable evidence set.</p></div><button class="primary" data-action="context-ai" data-kind="Collective role simulation">Prepare a grounded turn</button></div>
    <div class="callout warning-callout"><strong>Important limitation:</strong> multiple labels do not create independent agents, validated expertise, or human collective intelligence. All roles use the configured model unless you deliberately run separate providers.</div>
    <div class="three-column settings-section"><article class="card"><h3>Information conditions</h3><p>State which sources each role may see. The transmission preview is the authoritative disclosure.</p></article><article class="card"><h3>Interaction protocol</h3><p>Use ordered rounds and keep model responses separate from researcher observations.</p></article><article class="card"><h3>Outcome discipline</h3><p>Do not treat agreement as truth. Compare citations, uncertainty, and missing evidence.</p></article></div>
    <article class="card settings-section"><h3>Recommended first experiment</h3><p>Ask a methods critic, a theory critic, and a boundary-condition critic to inspect the same saved evidence set one turn at a time. Record where their source-grounded concerns converge and where evidence is absent.</p><button class="secondary" data-action="context-ai" data-kind="Collective role simulation">Set up the first turn</button></article>
  </section>`;
}

async function renderIntegrations() {
  const [ai, jobs] = await Promise.all([window.atlas.ai.get(), window.atlas.indexingJobs()]);
  const config = ai.configuration;
  const providerInfo = ai.providers[config.provider] ?? ai.providers.ollama;
  const credential = ai.credential;
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>Integrations</h2><p>Local source folders, recoverable exports, and optional AI providers. Core research work remains available without AI.</p></div></div>
    <article class="card"><div class="card-header"><div><h3>Local research sources</h3><p>Research Atlas reads PDFs where they live and writes only to its own database.</p></div><div class="button-row"><button class="secondary compact" data-action="add-pdfs">Add PDFs</button><button class="primary compact" data-action="add-folder">Choose or refresh folder</button></div></div>
      ${jobs.length ? `<ul class="activity-list">${jobs.slice(0, 6).map((job) => `<li><span class="${job.status === 'Failed' ? 'danger-text' : 'good'}">${job.status === 'Failed' ? '!' : '✓'}</span><div><strong>${escapeHTML(job.source_name)}</strong><small>${escapeHTML(job.status)} · ${job.completed_units}/${job.total_units ?? '?'} · ${formatDate(job.updated_at)}</small>${job.failure_message ? `<p class="danger-text">${escapeHTML(job.failure_message)}</p>` : ''}</div></li>`).join('')}</ul>` : '<p>No indexing activity recorded yet.</p>'}
    </article>
    <article class="card settings-section"><div class="card-header"><div><h3>AI provider</h3><p>Local models are preferred. Hosted transmission is off until explicitly enabled.</p></div><span id="credential-pill" class="pill ${credential.session || credential.persistent || !credential.required ? 'success' : ''}">${!credential.required ? 'No key required' : credential.session ? 'Session key ready' : credential.persistent ? 'Secure key stored' : 'Key required'}</span></div>
      <form id="ai-settings" class="settings-grid">
        <label>Provider<select name="provider">${Object.entries(ai.providers).map(([key, item]) => `<option value="${key}" ${key === config.provider ? 'selected' : ''}>${escapeHTML(item.label)}</option>`).join('')}</select></label>
        <label>Model identifier<input name="model" value="${escapeHTML(config.model)}" autocomplete="off"></label>
        <label class="full">API endpoint<input name="endpoint" value="${escapeHTML(config.endpoint)}" autocomplete="off"></label>
        <label>Maximum source passages<input name="maximum_passages" type="number" min="1" max="50" value="${config.maximum_passages}"></label>
        <label>Maximum output tokens<input name="maximum_output_tokens" type="number" min="128" max="32000" value="${config.maximum_output_tokens}"></label>
        <label>Reasoning effort<select name="reasoning_effort"><option>low</option><option ${config.reasoning_effort === 'medium' ? 'selected' : ''}>medium</option><option ${config.reasoning_effort === 'high' ? 'selected' : ''}>high</option></select></label>
        <label>Hosted AI transmission<select name="external_transmission_enabled"><option value="false" ${!config.external_transmission_enabled ? 'selected' : ''}>Off</option><option value="true" ${config.external_transmission_enabled ? 'selected' : ''}>On — still preview every request</option></select></label>
        <label class="full">API key (never written to SQLite or exports)<input id="api-key" type="password" autocomplete="new-password" placeholder="${providerInfo.credential ? 'Paste a new or replacement key' : 'Not required for this local provider'}"></label>
        <div class="full status-line"><span class="status-dot"></span><span>${escapeHTML(credential.security.explanation)}</span></div>
        <div class="button-row full"><button class="primary" type="submit">Save AI settings</button><button class="secondary" type="button" data-action="store-session-key">Use key this session</button><button class="secondary" type="button" data-action="store-secure-key" ${credential.security.available ? '' : 'disabled'}>Store securely</button><button class="secondary" type="button" data-action="remove-key">Remove key</button><button id="test-ai" class="secondary" type="button">Test connection</button></div>
      </form>
      <div id="connection-result" class="status-line settings-section"></div>
    </article>
    <article class="card settings-section"><div class="card-header"><div><h3>Export and recovery</h3><p>Backups preserve the complete workspace. Portable JSON is human-readable and suitable for migration.</p></div></div><div class="button-row"><button class="primary" data-action="backup">Back up database…</button><button class="secondary" data-action="export">Export portable JSON…</button><button class="secondary" data-action="show-data">Show local database</button></div></article>
    <article class="card settings-section"><h3>Where your data lives</h3><p><code>${escapeHTML(state.bootstrap.userDataPath)}</code></p><p>Do not place this live database inside Dropbox, OneDrive, iCloud Drive, or another synchronised folder. Use Research Atlas backups for transfer instead.</p></article>
  </section>`;

  const form = $('#ai-settings');
  const keyInput = $('#api-key');
  const currentPayload = () => {
    const values = Object.fromEntries(new FormData(form));
    return { ...values, external_transmission_enabled: values.external_transmission_enabled === 'true' };
  };
  form.elements.provider.addEventListener('change', (event) => {
    const selected = ai.providers[event.target.value];
    form.elements.endpoint.value = selected.endpoint;
    form.elements.model.value = selected.model;
    keyInput.placeholder = selected.credential ? 'Paste a new or replacement key' : 'Not required for this local provider';
  });
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    await perform(() => window.atlas.ai.save(currentPayload()), 'AI settings saved.');
    await renderIntegrations();
  });
  $('[data-action="store-session-key"]').addEventListener('click', async () => {
    await perform(() => window.atlas.ai.storeCredential(form.elements.provider.value, keyInput.value, 'session'), 'API key is available for this app session only.');
    keyInput.value = ''; await renderIntegrations();
  });
  $('[data-action="store-secure-key"]').addEventListener('click', async () => {
    await perform(() => window.atlas.ai.storeCredential(form.elements.provider.value, keyInput.value, 'secure'), 'API key encrypted by the operating system.');
    keyInput.value = ''; await renderIntegrations();
  });
  $('[data-action="remove-key"]').addEventListener('click', async () => {
    await perform(() => window.atlas.ai.removeCredential(form.elements.provider.value), 'Stored and session credentials removed.');
    await renderIntegrations();
  });
  $('#test-ai').addEventListener('click', async () => {
    const button = $('#test-ai'); button.disabled = true; button.textContent = 'Testing…';
    try {
      const result = await perform(() => window.atlas.ai.test(currentPayload(), keyInput.value));
      $('#connection-result').innerHTML = `<span class="good">✓</span><span>${escapeHTML(result.message)}</span>`;
    } catch { $('#connection-result').innerHTML = '<span class="danger-text">!</span><span>Connection test failed. Review the message above.</span>'; }
    finally { button.disabled = false; button.textContent = 'Test connection'; }
  });
}

function renderLearning() {
  const lessons = [
    ['1. Add your source folder', 'Open Integrations, choose the folder containing your PDFs, and wait for indexing to finish. The originals are never edited.'],
    ['2. Check source identity', 'Open Literature Library. Confirm title, author, year, availability, file location, fingerprint, and indexed page count.'],
    ['3. Frame a research question', 'Create a question with objectives, theoretical interests, definitions, disagreements, hypotheses, and methodological considerations.'],
    ['4. Find exact passages', 'Search in Evidence Explorer. Quotation marks require an exact phrase; filter to PDF passages when you need source text.'],
    ['5. Build a qualified argument', 'Record the proposition separately from its qualification. Treat missing boundaries as a review prompt.'],
    ['6. Use the Reading Desk', 'Read the original PDF inside Research Atlas. Page text in search is an index, not a replacement for inspecting the source.'],
    ['7. Use AI safely', 'Choose a provider in Integrations. Select papers, write a bounded task, preview every exact passage, then approve one request.'],
    ['8. Verify model output', 'Check each [S#] citation against the supplied passage. Model output remains review required until you decide otherwise.'],
    ['9. Back up before major changes', 'Use Integrations → Back up database. Keep the backup somewhere separate from the live database.'],
    ['10. Move to another computer', 'Install the build for that operating system, copy your PDFs normally, and use a portable export or validated database backup.']
  ];
  $('#content').innerHTML = `<section class="page"><div class="page-heading"><div><h2>Learn Research Atlas</h2><p>A complete first-hour route from local source files to traceable research reasoning.</p></div><button class="primary" data-action="add-folder">Start with my folder</button></div>
    <div class="platform-grid"><article class="platform-card"><strong>macOS</strong><span>Open the signed DMG, drag Research Atlas to Applications, then launch it from Applications.</span></article><article class="platform-card"><strong>Windows</strong><span>Run Research-Atlas-Setup.exe. Windows may ask you to confirm the signed publisher.</span></article><article class="platform-card"><strong>Linux</strong><span>Install the DEB or RPM for your distribution. Use GNOME Keyring, KWallet, or session-only API keys.</span></article></div>
    <div class="two-column"><article class="card"><div class="card-header"><h3>First-hour workflow</h3><span class="pill">10 lessons</span></div><ul class="lesson-list">${lessons.map(([title, description]) => `<li><button><strong>${escapeHTML(title)}</strong><span>${escapeHTML(description)}</span></button></li>`).join('')}</ul></article><aside><article class="card"><h3>Three rules worth remembering</h3><ol><li>Your PDFs remain the source of truth.</li><li>An indexed passage is not automatically evidence for a claim.</li><li>AI never sends research until you inspect and approve the request.</li></ol></article><article class="card settings-section"><h3>Need exact installation help?</h3><p>The repository includes a platform-by-platform installation and troubleshooting handbook with screenshots of the real app interface.</p><button class="secondary" data-route-link="integrations">Review system status</button></article></aside></div>
  </section>`;
}

async function openRecordDialog(resource, id = null) {
  const pageConfig = Object.values(resourcePages).find((item) => item.resource === resource);
  if (!pageConfig) return;
  const records = await window.atlas.resources.list(resource);
  const record = records.find((item) => item.id === id) ?? {};
  if (resource === 'questions' && !record.project_id) {
    const projects = await window.atlas.resources.list('projects');
    record.project_id = projects[0]?.id;
    if (!record.project_id) { toast('Create a project before adding a research question.', true); return; }
  }
  state.editingResource = resource; state.editingRecord = record;
  $('#record-title').textContent = `${record.id ? 'Edit' : 'New'} ${pageConfig.noun}`;
  $('#record-fields').innerHTML = `${resource === 'questions' ? `<input type="hidden" name="project_id" value="${escapeHTML(record.project_id)}">` : ''}${pageConfig.fields.map(([name, label, type, required, options]) => {
    const value = record[name] ?? '';
    if (type === 'textarea') return `<label class="long">${escapeHTML(label)}<textarea name="${name}" rows="${name === 'question' || name === 'proposition' ? 4 : 3}" ${required ? 'required' : ''}>${escapeHTML(value)}</textarea></label>`;
    if (type === 'select') return `<label>${escapeHTML(label)}<select name="${name}">${options.map((option) => `<option ${value === option ? 'selected' : ''}>${escapeHTML(option)}</option>`).join('')}</select></label>`;
    return `<label class="${required ? 'long' : ''}">${escapeHTML(label)}<input name="${name}" value="${escapeHTML(value)}" ${required ? 'required' : ''}></label>`;
  }).join('')}`;
  $('#record-dialog').showModal();
}

async function confirmAction(title, message) {
  $('#confirm-title').textContent = title;
  $('#confirm-message').textContent = message;
  const dialog = $('#confirm-dialog');
  dialog.showModal();
  return new Promise((resolve) => dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true }));
}

async function openAiDialog(context = {}) {
  state.aiContext = context;
  state.aiPreviewReady = false;
  const [library, ai] = await Promise.all([window.atlas.library.list({ availability: 'Available' }), window.atlas.ai.get()]);
  $('#ai-query').value = context.query || '';
  $('#ai-kind').value = context.kind || 'Assistant';
  const selectedIds = new Set(context.literatureIds || (context.paperId ? [context.paperId] : []));
  $('#ai-source-picker').innerHTML = `<div class="list-pane-header"><strong>Select sources</strong> · ${library.length} available</div>${library.length ? library.map((paper) => `<label class="source-option"><input type="checkbox" value="${paper.id}" ${selectedIds.has(paper.id) ? 'checked' : ''}><span><strong>${escapeHTML(paper.title)}</strong><br>${escapeHTML(paper.authors || 'Unknown author')} · ${paper.publication_year || 'Year unavailable'}</span></label>`).join('') : '<div class="empty-state compact-empty"><p>Add PDFs before requesting source-grounded analysis.</p></div>'}`;
  $('#ai-preview').innerHTML = `<div class="empty-state compact-empty"><span>◎</span><h3>Preview before sending</h3><p>${ai.configuration.provider === 'ollama' || ai.configuration.provider === 'lmstudio' ? 'This provider is local, but the exact prompt and sources are still shown before the request.' : 'Hosted transmission is never automatic. Inspect the exact destination and passages first.'}</p></div>`;
  $('#send-ai').disabled = true;
  $('#send-ai').textContent = 'Approve and send once';
  $('#ai-dialog').showModal();
}

function selectedAiPapers() {
  return $$('#ai-source-picker input:checked').map((input) => input.value);
}

async function previewAi() {
  const request = { query: $('#ai-query').value, kind: $('#ai-kind').value, literatureIds: selectedAiPapers(), ...state.aiContext };
  if (!request.query.trim()) { toast('Enter a research task before previewing.', true); return; }
  const preview = await perform(() => window.atlas.ai.preview(request));
  state.aiPreviewReady = true;
  $('#send-ai').disabled = false;
  $('#ai-preview').innerHTML = `<p class="eyebrow">Exact one-time transmission</p><h3>${escapeHTML(preview.provider)} · ${escapeHTML(preview.model)}</h3><p><strong>Destination:</strong> ${escapeHTML(preview.endpoint)} ${preview.local ? '<span class="pill success">Local computer</span>' : '<span class="pill">Hosted service</span>'}</p><div class="source-block"><strong>Research task</strong><p>${escapeHTML(preview.query)}</p></div><p><strong>${preview.passages.length} source passage(s) · ${preview.characters.toLocaleString()} characters</strong></p>${preview.passages.map((passage, index) => `<div class="source-block"><strong>[S${index + 1}] ${escapeHTML(passage.title)} · page ${passage.page}</strong><p>${escapeHTML(passage.passage_text)}</p></div>`).join('') || '<div class="callout warning-callout">No source passages will be supplied. The model must not make claims about your literature.</div>'}`;
}

async function runAi() {
  if (!state.aiPreviewReady) return;
  const button = $('#send-ai'); button.disabled = true; button.textContent = 'Waiting for model…';
  const request = { query: $('#ai-query').value, kind: $('#ai-kind').value, literatureIds: selectedAiPapers(), ...state.aiContext };
  try {
    const result = await perform(() => window.atlas.ai.run(request));
    $('#ai-preview').innerHTML = `<p class="eyebrow">Review required</p><h3>Model response</h3><div class="callout warning-callout">Check every citation against the supplied source passage. This response has not changed any research record.</div><div class="source-block answer">${escapeHTML(result.response)}</div><p class="status-line">Saved as analysis ${escapeHTML(result.analysisId)}.</p>`;
    button.textContent = 'Request complete';
    toast('Analysis saved for review.');
  } catch { button.disabled = false; button.textContent = 'Approve and send once'; }
}

$('#content').addEventListener('click', async (event) => {
  const routeLink = event.target.closest('[data-route-link]');
  if (routeLink) { go(routeLink.dataset.routeLink); return; }
  const paper = event.target.closest('[data-paper]');
  if (paper) { await renderPaperDetail(paper.dataset.paper); return; }
  const action = event.target.closest('[data-action]');
  if (!action) return;
  const name = action.dataset.action;
  if (name === 'retry') go(state.route);
  else if (name === 'add-pdfs') addPDFs();
  else if (name === 'add-folder') addFolder();
  else if (name === 'open-ai') openAiDialog();
  else if (name === 'new-record') openRecordDialog(action.dataset.resource);
  else if (name === 'edit-record') openRecordDialog(action.dataset.resource, action.dataset.id);
  else if (name === 'delete-record') {
    if (await confirmAction('Delete this research record?', 'Related records may also be removed by database integrity rules. This cannot be undone.')) {
      await perform(() => window.atlas.resources.delete(action.dataset.resource, action.dataset.id), 'Record deleted.');
      await go(state.route);
    }
  } else if (name === 'read-paper') { state.selectedPaperId = action.dataset.id; go('reading'); }
  else if (name === 'paper-ai') openAiDialog({ paperId: action.dataset.id, literatureIds: [action.dataset.id], query: 'Analyse the strongest findings, limitations, and unresolved questions in this paper.' });
  else if (name === 'context-ai') openAiDialog({ kind: action.dataset.kind || 'Assistant' });
  else if (name === 'record-ai') {
    const records = await window.atlas.resources.list(action.dataset.resource);
    const record = records.find((item) => item.id === action.dataset.id);
    const title = record?.proposition || record?.question || record?.title || record?.name || '';
    openAiDialog({ kind: action.dataset.kind || 'Assistant', targetType: action.dataset.resource, targetId: action.dataset.id,
      query: `Critically examine this recorded ${action.dataset.resource.replace(/s$/, '')}: ${title}` });
  } else if (name === 'backup') {
    const target = await perform(() => window.atlas.data.backup()); if (target) toast(`Backup saved: ${target}`);
  } else if (name === 'export') {
    const target = await perform(() => window.atlas.data.export()); if (target) toast(`Export saved: ${target}`);
  } else if (name === 'show-data') window.atlas.data.showFolder();
});

$('#record-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const record = { ...state.editingRecord, ...Object.fromEntries(new FormData(event.currentTarget)) };
  await perform(() => window.atlas.resources.save(state.editingResource, record), 'Research record saved.');
  $('#record-dialog').close();
  await go(state.route);
});

$$('.close-dialog').forEach((button) => button.addEventListener('click', () => button.closest('dialog').close()));
$('#preview-ai').addEventListener('click', previewAi);
$('#ai-form').addEventListener('submit', (event) => { event.preventDefault(); runAi(); });
$('#ai-query').addEventListener('input', () => { state.aiPreviewReady = false; $('#send-ai').disabled = true; });
$('#ai-source-picker').addEventListener('change', () => { state.aiPreviewReady = false; $('#send-ai').disabled = true; });
$('#global-search').addEventListener('click', () => go('search'));
$('#open-ai').addEventListener('click', () => openAiDialog());
$('#quick-add').addEventListener('click', addPDFs);

window.atlas.library.onProgress((progress) => {
  const banner = $('#index-progress');
  banner.classList.remove('hidden');
  banner.textContent = `Indexing ${progress.completed}/${progress.total}: ${progress.imported} new, ${progress.duplicates} already known, ${progress.failures.length} failed`;
  if (progress.completed === progress.total) setTimeout(() => banner.classList.add('hidden'), 4_000);
});

window.atlas.onCommand((command) => {
  if (command === 'add-pdfs') addPDFs();
  else if (command === 'add-folder') addFolder();
  else if (command === 'search') go('search');
  else if (command === 'learning') go('learning');
});

document.addEventListener('keydown', (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') { event.preventDefault(); go('search'); }
  if (event.key === 'Escape') $$('dialog[open]').forEach((dialog) => dialog.close());
});

async function start() {
  buildNavigation();
  state.bootstrap = await window.atlas.bootstrap();
  const requestedRoute = new URLSearchParams(window.location.search).get('route');
  await go(requestedRoute && titles[requestedRoute] ? requestedRoute : 'home');
}

start().catch((error) => {
  $('#content').innerHTML = `<div class="empty-state"><span>!</span><h3>Research Atlas could not start</h3><p>${escapeHTML(error?.message || error)}</p></div>`;
});
