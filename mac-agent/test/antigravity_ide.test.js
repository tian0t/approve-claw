const { test } = require('node:test');
const assert = require('node:assert');
const ConfirmationDetector = require('../src/detector');

test('detects Antigravity IDE Tool Sandbox permission prompt', () => {
  const d = new ConfirmationDetector();
  const samplePrompt = `
Let's test all modified JS files for syntax correctness using run_command.

Run node -c pages/home/home.js && node -c pages/my/my.js?

~/Desktop/yi $ node -c pages/home/home.js && node -c pages/my/my.js

Waiting for user input

🔒 Allow checking syntax of home.js and my.js?
⚠️ Confirm the command is safe to run outside of the sandbox with full network and disk access.
node -c pages/home/home.js

1 Yes, allow this time
2 Yes, and always allow 'node -c pages/home/home.js' in this conversation
3 Yes, and always allow 'node -c pages/home/home.js' when not in a project
4 Yes, and always allow 'node -c pages/home/home.js'
5 No (tell the agent what to do instead)

Skip  Submit ↵
`;

  d.feed(samplePrompt);
  const req = d.detect('Antigravity');

  console.log("Extracted Request:", req);

  assert.ok(req, 'should detect Antigravity IDE prompt');
  assert.equal(req.agent, 'Antigravity IDE');
  assert.ok(req.isIdePrompt, 'should mark as isIdePrompt');
  assert.ok(req.command.includes('node -c pages/home/home.js'), 'should extract target tool command');
});
