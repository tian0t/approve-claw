const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

class VisionBridge {
  constructor(server) {
    this.server = server;
    this.child = null;
    this.binaryPath = path.join(__dirname, '../bin/vision_observer');
    this.activePromptId = null;

    if (this.server) {
      const originalOnDecision = this.server.onDecision;
      this.server.onDecision = (requestId, action) => {
        if (originalOnDecision) {
          originalOnDecision(requestId, action);
        }
        this.handleDecision(requestId, action);
      };
    }
  }

  start() {
    if (!fs.existsSync(this.binaryPath)) {
      console.warn('[Vision Bridge] Binary not found at:', this.binaryPath);
      return;
    }

    try {
      this.child = spawn(this.binaryPath, [], {
        stdio: ['pipe', 'pipe', 'inherit'],
      });

      let buffer = '';
      this.child.stdout.on('data', (chunk) => {
        buffer += chunk.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop();

        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            const msg = JSON.parse(line.trim());
            this.handleVisionMessage(msg);
          } catch (e) {
            // Ignore non-json lines
          }
        }
      });

      this.child.on('exit', (code) => {
        console.log(`[Vision Bridge] vision_observer exited (${code}). Respawning in 3s...`);
        setTimeout(() => this.start(), 3000);
      });

      console.log('👁️  Universal Apple Vision OCR Screen Observer started.');
    } catch (e) {
      console.error('[Vision Bridge] Failed to start vision_observer:', e.message);
    }
  }

  handleVisionMessage(msg) {
    if (msg.type === 'vision_ready') {
      console.log('[Vision Bridge] Native Vision Engine is active and scanning screen.');
    } else if (msg.type === 'vision_prompt_detected') {
      console.log(`\n👁️  [Vision OCR] Detected Agent Confirmation on Screen:`);
      console.log(`    Agent:   ${msg.agent}`);
      console.log(`    Command: ${msg.command}`);
      console.log(`    Risk:    ${msg.risk.toUpperCase()}`);

      this.activePromptId = msg.id;

      const request = {
        id: msg.id,
        agent: msg.agent || 'AI Agent',
        type: 'command_confirmation',
        title: msg.title || 'Permission Required',
        command: msg.command,
        description: msg.description,
        risk: msg.risk || 'medium',
        time: new Date().toISOString(),
        options: msg.options || ['approve', 'reject'],
        optionsList: msg.optionsList || [
          { key: 'approve', label: 'Allow / Approve', isPrimary: true, isDestructive: false },
          { key: 'reject', label: 'Deny / Reject', isPrimary: false, isDestructive: true }
        ],
        isVisionPrompt: true,
      };

      if (this.server) {
        this.server.sendRequest(request);
      }
    } else if (msg.type === 'prompt_cleared') {
      console.log('[Vision OCR] Screen prompt cleared.');
      if (this.activePromptId && this.server) {
        this.server.broadcastCleared(this.activePromptId);
        this.activePromptId = null;
      }
    } else if (msg.type === 'keystroke_dispatched') {
      console.log(`✨ [Vision Keystroke] Keystroke dispatched for action: '${msg.action}'`);
    }
  }

  handleDecision(requestId, action) {
    if (!this.child || !this.child.stdin || !this.child.stdin.writable) return;

    if (this.activePromptId && requestId === this.activePromptId) {
      console.log(`[Vision Bridge] Forwarding mobile decision '${action}' to Screen Vision Keystroke Dispatcher...`);
      const cmdPayload = JSON.stringify({
        action: action,
        promptId: requestId,
      });

      this.child.stdin.write(`${cmdPayload}\n`);
      if (this.server) {
        this.server.broadcastCleared(requestId);
      }
      this.activePromptId = null;
    }
  }

  stop() {
    if (this.child) {
      this.child.kill();
    }
  }
}

module.exports = VisionBridge;
