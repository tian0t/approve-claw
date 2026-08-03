const crypto = require('crypto');

// Matches choice markers for Codex, Claude Code, Kun (Kimi), and Antigravity:
// e.g., "Allow? (y/n) ", "Proceed? (Y/n) >", "[y/n]:", "(是/否)", "允许运行? (y/n)"
const PROMPT_REGEX = /(?:\([yY]\/[nN]\)|\[[yY]\/[nN]\]|\(是\/否\)|\[是\/否\]|\[确认\/取消\])\s*[>›:#]?\s*$/;

// Matches Antigravity IDE & AGY Tool Sandbox Permission Prompts:
// e.g., "Allow checking syntax...", "Confirm the command is safe to run outside of the sandbox", "1 Yes, allow this time"
const ANTIGRAVITY_IDE_PROMPT_REGEX = /(?:Confirm the command is safe to run|1\s*Yes,\s*allow|Yes,\s*and\s*always\s*allow|Allow\s+[\s\S]+?\?)/i;

class ConfirmationDetector {
  constructor() {
    this.buffer = '';
    this.maxBufferSize = 8192;
    this.pendingRequest = null;
    this.lastMatchEndOffset = 0;
  }

  feed(data) {
    this.buffer += this.stripAnsi(data);
    if (this.buffer.length > this.maxBufferSize) {
      this.buffer = this.buffer.slice(-this.maxBufferSize);
      this.lastMatchEndOffset = 0;
    }
  }

  clear() {
    this.buffer = '';
    this.pendingRequest = null;
    this.lastMatchEndOffset = 0;
  }

  acknowledge() {
    this.pendingRequest = null;
  }

  detect(agentName = 'AI Agent') {
    if (this.pendingRequest) {
      return null;
    }

    const searchStart = Math.min(this.lastMatchEndOffset, this.buffer.length);
    const tail = this.buffer.slice(searchStart);
    const recent = tail.slice(-1200);
    
    // Check standard (y/n) prompt
    let match = recent.match(PROMPT_REGEX);
    let isAntigravityIde = false;

    // Check Antigravity IDE tool sandbox permission prompt
    if (!match && ANTIGRAVITY_IDE_PROMPT_REGEX.test(recent)) {
      match = recent.match(ANTIGRAVITY_IDE_PROMPT_REGEX);
      isAntigravityIde = true;
    }

    if (!match) {
      return null;
    }

    const localEnd = match.index + match[0].length;
    this.lastMatchEndOffset = searchStart + (tail.length - recent.length) + localEnd;

    const commandInfo = this.extractCommand(isAntigravityIde);
    const optionsList = this.extractOptionsList(isAntigravityIde);

    this.pendingRequest = {
      id: 'req_' + crypto.randomBytes(4).toString('hex'),
      agent: isAntigravityIde ? 'Antigravity IDE' : agentName,
      type: 'command_confirmation',
      title: isAntigravityIde ? (commandInfo.description || 'Tool Sandbox Permission Required') : 'Permission Required',
      command: commandInfo.command,
      description: commandInfo.description,
      risk: this.assessRisk(commandInfo.command),
      time: new Date().toISOString(),
      options: optionsList.map((o) => o.key),
      optionsList: optionsList,
      isIdePrompt: isAntigravityIde,
    };

    return this.pendingRequest;
  }

  extractOptionsList(isAntigravityIde = false) {
    const lines = this.buffer.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    const options = [];

    if (isAntigravityIde) {
      for (const line of lines) {
        const match = line.match(/^([1-9])\s+(.*)$/);
        if (match) {
          const key = match[1];
          const rawLabel = match[2];
          const isDestructive = key === '5' || /No\s/i.test(rawLabel);
          options.push({
            key: key,
            label: `${key}. ${rawLabel}`,
            isPrimary: key === '1',
            isDestructive: isDestructive
          });
        }
      }
    }

    if (options.length === 0) {
      return [
        { key: 'approve', label: '1. Yes, Approve', isPrimary: true, isDestructive: false },
        { key: 'reject', label: '2. No, Reject', isPrimary: false, isDestructive: true }
      ];
    }

    return options;
  }

  extractCommand(isAntigravityIde = false) {
    const lines = this.buffer.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    let command = 'Unknown Command';
    let description = 'Confirmation prompt detected.';

    if (lines.length > 0) {
      if (isAntigravityIde) {
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          if (/Allow\s+/i.test(line) || /Confirm the command is safe/i.test(line)) {
            description = line;
            for (let j = i + 1; j < lines.length; j++) {
              const nextLine = lines[j];
              if (!/^(Confirm|🔒|⚠️|1|2|3|4|5|Yes|No|Skip|Submit)/i.test(nextLine) && nextLine.length > 2) {
                command = this.normalizeCommand(nextLine);
                return { command, description };
              }
            }
          }
        }
        
        for (let i = 0; i < lines.length; i++) {
          const line = lines[i];
          if (/^(node|npm|yarn|pnpm|git|python|bash|sh|zsh|npx|cargo|go|make|docker|chmod|rm|sudo)/i.test(line)) {
            command = this.normalizeCommand(line);
            return { command, description: 'Antigravity IDE Tool Execution' };
          }
        }
      }

      for (let i = lines.length - 1; i >= 0; i--) {
        const line = lines[i];
        if (/\b(wants to run|wants to execute|wants to run the following command|command:|允许运行|请求执行命令)/i.test(line)) {
          if (i + 1 < lines.length) {
            command = this.normalizeCommand(lines[i + 1]);
            description = line;
            return { command, description };
          }
        }
      }

      for (let i = lines.length - 1; i >= 0; i--) {
        const line = lines[i];
        if (this.isPromptLine(line)) {
          const rest = line
            .replace(/(?:allow|approve|continue|confirm|proceed|try anyway|允许|执行|确认|继续)\?\s*(?:\([yY]\/[nN]\)|\[[yY]\/[nN]\]|\(是\/否\)|\[是\/否\])?[>›:#]?\s*$/i, '')
            .replace(/(?:\([yY]\/[nN]\)|\[[yY]\/[nN]\]|\(是\/否\)|\[是\/否\])\s*[>›:#]?\s*$/, '')
            .trim();
          if (rest && !/^(do|are|would|should|can|may|is|did|could|does)\s/i.test(rest) && !/\?$/.test(rest)) {
            command = this.normalizeCommand(rest);
            description = 'Confirmation prompt detected.';
            return { command, description };
          }
          continue;
        }
        command = this.normalizeCommand(line);
        const ctxStart = Math.max(0, i - 3);
        description = lines.slice(ctxStart, i).join('\n') || 'Confirmation prompt detected.';
        return { command, description };
      }

      const lastLine = lines[lines.length - 1];
      command = this.isPromptLine(lastLine) ? 'Unknown Command' : this.normalizeCommand(lastLine);
    }

    return { command, description };
  }

  isPromptLine(line) {
    return /(?:\([yY]\/[nN]\)|\[[yY]\/[nN]\]|\(是\/否\)|\[是\/否\]|allow\?|approve\?|continue\?|confirm\?|proceed\?|try anyway\?|允许\?|确认\?|执行\?|Yes,\s*allow)/i.test(line);
  }

  normalizeCommand(line) {
    return line
      .replace(/^[>›❯➜#$]\s*/, '')
      .replace(/^\d+\s*/, '')
      .replace(/^[•*\-\+]\s*/, '')
      .trim();
  }

  assessRisk(command) {
    const cmd = command.toLowerCase();
    const highRiskKeywords = [
      'rm ', 'rmdir', 'drop table', 'drop database', 'delete from', 'truncate',
      'chmod 777', 'chmod -r', 'sudo ', 'mkfs', 'dd ', 'docker rm', 'docker rmi',
      'docker system prune', 'kill -9', 'git push -f', 'git push --force',
      'git reset --hard', '> /dev/null', 'destroy', 'format', ':(){', '| sh',
      '| bash', '| zsh',
    ];

    const lowRiskKeywords = [
      'npm install', 'npm test', 'npm run', 'yarn', 'pnpm', 'git status',
      'git pull', 'git diff', 'git log', 'git branch', 'pytest', 'ls ',
      'pwd', 'echo ', 'cat ', 'cd ', 'python', 'node ', 'go test', 'cargo',
    ];

    if (highRiskKeywords.some((kw) => cmd.includes(kw))) {
      return 'high';
    }

    if (lowRiskKeywords.some((kw) => cmd.includes(kw))) {
      return 'low';
    }

    return 'medium';
  }

  stripAnsi(str) {
    return String(str)
      .replace(/\u001b\[[0-9;?]*[ -\/]*[@-~]/g, '')
      .replace(/\u001b\][^\u0007]*(?:\u0007|\u001b\\)/g, '')
      .replace(/\u001b[\u0040-\u005F]/g, '')
      .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '');
  }
}

module.exports = ConfirmationDetector;
