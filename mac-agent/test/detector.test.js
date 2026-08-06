const { test } = require('node:test');
const assert = require('node:assert');
const ConfirmationDetector = require('../src/detector');
const { detectAgent, AGENT_LABELS } = require('../src/terminal');

test('detects npm install as low risk', () => {
  const d = new ConfirmationDetector();
  d.feed('\nClaude Code wants to run the following command:\n  npm install lodash\n\nAllow? (y/n) ');
  const r = d.detect('Claude Code');
  assert.ok(r, 'should detect a request');
  assert.equal(r.command, 'npm install lodash');
  assert.equal(r.risk, 'low');
  assert.equal(r.agent, 'Claude Code');
});

test('detects rm -rf as high risk', () => {
  const d = new ConfirmationDetector();
  d.feed('\nClaude Code wants to run:\n  rm -rf ./build\n\nAllow? (y/n) ');
  const r = d.detect();
  assert.ok(r);
  assert.equal(r.risk, 'high');
});

test('detects Codex CLI prompts', () => {
  const d = new ConfirmationDetector();
  d.feed('\n[Codex] Execute this command?\n  git push --force origin main\nConfirm action: (y/n) ');
  const r = d.detect('Codex');
  assert.ok(r);
  assert.equal(r.agent, 'Codex');
  assert.equal(r.risk, 'high');
});

test('detects Codex CLI "Allow execution" prompts', () => {
  const d = new ConfirmationDetector();
  d.feed('\nCodex wants to execute:\n  rm -rf ./node_modules\nAllow execution of command? (y/n/always) ');
  const r = d.detect('Codex');
  assert.ok(r);
  assert.equal(r.agent, 'Codex');
  assert.equal(r.command, 'rm -rf ./node_modules');
  assert.equal(r.risk, 'high');
  assert.equal(r.isCodexPrompt, true);
});

test('detects Kun (Kimi) Chinese prompts', () => {
  const d = new ConfirmationDetector();
  d.feed('\n[Kun Agent] 允许运行以下命令吗？\n  python train.py --epochs 100\n允许运行? (y/n) ');
  const r = d.detect('Kun (Kimi)');
  assert.ok(r);
  assert.equal(r.agent, 'Kun (Kimi)');
});

test('detects Google Antigravity prompts', () => {
  const d = new ConfirmationDetector();
  d.feed('\n[Antigravity] Proposed execution step:\n  npx create-vite-app ./my-app\nApprove execution? [y/n] ');
  const r = d.detect('Antigravity');
  assert.ok(r);
  assert.equal(r.agent, 'Antigravity');
  assert.equal(r.risk, 'medium');
});

test('detectAgent function correctly matches all 4 agents', () => {
  assert.equal(AGENT_LABELS[detectAgent('claude', [])], 'Claude Code');
  assert.equal(AGENT_LABELS[detectAgent('codex', ['run'])], 'Codex');
  assert.equal(AGENT_LABELS[detectAgent('kun', ['start'])], 'Kun');
  assert.equal(AGENT_LABELS[detectAgent('kimi', ['chat'])], 'Kun (Kimi)');
  assert.equal(AGENT_LABELS[detectAgent('antigravity', [])], 'Antigravity');
  assert.equal(AGENT_LABELS[detectAgent('agy', [])], 'Antigravity');
});

test('does not trigger on plain text without a choice marker', () => {
  const d = new ConfirmationDetector();
  d.feed('some random output with no prompt\n  ls -la\n');
  assert.equal(d.detect(), null);
});

test('does not trigger on a bare "continue?" question', () => {
  const d = new ConfirmationDetector();
  d.feed('Do you want to continue?\n');
  assert.equal(d.detect(), null);
});

test('does not re-trigger on the same prompt without new output', () => {
  const d = new ConfirmationDetector();
  d.feed('\nAllow? (y/n) ');
  assert.ok(d.detect());
  d.acknowledge();
  assert.equal(d.detect(), null);
});

test('triggers again on a new prompt after a decision', () => {
  const d = new ConfirmationDetector();
  d.feed('\nClaude Code wants to run the following command:\n  npm install lodash\n\nAllow? (y/n) ');
  assert.ok(d.detect());
  d.acknowledge();
  d.feed('n\r\nCommand rejected.\n\nClaude Code wants to run:\n  rm -rf ./build\n\nAllow? (y/n) ');
  const r = d.detect();
  assert.ok(r);
  assert.equal(r.command, 'rm -rf ./build');
  assert.equal(r.risk, 'high');
});

test('strips ANSI escape codes before matching', () => {
  const d = new ConfirmationDetector();
  d.feed('\x1b[32mClaude Code wants to run:\x1b[0m\n  \x1b[1msudo\x1b[0m make install\n\n\x1b[36mAllow? (y/n) \x1b[0m');
  const r = d.detect();
  assert.ok(r);
  assert.ok(r.command.includes('sudo'), 'command should include sudo');
});
