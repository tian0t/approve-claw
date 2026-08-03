const pty = require('node-pty');

const AGENT_LABELS = {
  claude: 'Claude Code',
  codex: 'Codex',
  kun: 'Kun',
  kimi: 'Kun (Kimi)',
  antigravity: 'Antigravity',
  default: 'AI Agent',
};

const AGENT_KEYS = {
  claude: { approve: 'y\r', reject: 'n\r' },
  codex: { approve: 'y\r', reject: 'n\r' },
  kun: { approve: 'y\r', reject: 'n\r' },
  kimi: { approve: 'y\r', reject: 'n\r' },
  antigravity: { approve: 'y\r', reject: 'n\r' },
  default: { approve: 'y\r', reject: 'n\r' },
};

function detectAgent(command, args) {
  const name = `${command} ${args.join(' ')}`.toLowerCase();
  if (name.includes('claude')) return 'claude';
  if (name.includes('codex')) return 'codex';
  if (name.includes('kun')) return 'kun';
  if (name.includes('kimi') || name.includes('moonshot')) return 'kimi';
  if (name.includes('antigravity') || name.includes('agy')) return 'antigravity';
  return 'default';
}

function shellEscape(arg) {
  if (/[\s"'$*&|<>;()\\]/.test(arg)) {
    return `'${arg.replace(/'/g, "'\\''")}'`;
  }
  return arg;
}

function runTerminal(command, args, server, detector) {
  const agentKey = detectAgent(command, args);
  const agentLabel = AGENT_LABELS[agentKey] || AGENT_LABELS.default;
  const keys = AGENT_KEYS[agentKey] || AGENT_KEYS.default;

  if (process.stdin.isTTY) {
    process.stdin.setRawMode(true);
  }
  process.stdin.resume();
  process.stdin.setEncoding('utf8');

  const shell = process.env.SHELL || '/bin/zsh';
  const resolvedCommand = command === 'node' ? process.execPath : command;
  const commandString = [resolvedCommand, ...args].map(shellEscape).join(' ');

  const defaultPaths = [
    '/Users/yu./.local/bin',
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
    '/bin',
    '/usr/sbin',
    '/sbin',
    process.env.PATH || ''
  ].filter(Boolean).join(':');

  let ptyProcess;
  try {
    ptyProcess = pty.spawn(shell, ['-l', '-c', commandString], {
      name: 'xterm-256color',
      cols: process.stdout.columns || 80,
      rows: process.stdout.rows || 24,
      cwd: process.cwd(),
      env: { ...process.env, PATH: defaultPaths },
    });
  } catch (e) {
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(false);
    }
    throw e;
  }

  ptyProcess.onData((data) => {
    process.stdout.write(data);
    detector.feed(data);

    const request = detector.detect(agentLabel);
    if (request) {
      server.sendRequest(request);
    }
  });

  const onDataHandler = (data) => {
    ptyProcess.write(data);
  };
  process.stdin.on('data', onDataHandler);

  server.onDecision = (requestId, action) => {
    if (detector.pendingRequest && detector.pendingRequest.id === requestId) {
      const isIde = detector.pendingRequest.isIdePrompt;
      const defaultApproveKey = isIde ? '1\r' : keys.approve;
      const defaultRejectKey = isIde ? '5\r' : keys.reject;
      const charToSubmit = action === 'approve' ? defaultApproveKey : defaultRejectKey;
      console.log(`\n[CLAW Approve] Forwarding decision '${action}' (${JSON.stringify(charToSubmit)}) to ${agentLabel}...`);
      ptyProcess.write(charToSubmit);
      detector.acknowledge();
    }
  };

  ptyProcess.onExit(({ exitCode }) => {
    if (process.stdin.isTTY) {
      process.stdin.setRawMode(false);
    }
    process.stdin.pause();
    process.exit(exitCode);
  });
}

module.exports = {
  detectAgent,
  runTerminal,
  AGENT_LABELS,
};
