const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

class AxBridge {
  constructor(server, detector) {
    this.server = server;
    this.detector = detector;
    this.child = null;
    this.binaryPath = path.join(__dirname, '../bin/ax_observer');
    this.activePromptId = null;

    // Attach decision listener to WebSocket server
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
      console.warn('[AX Bridge] Binary not found at:', this.binaryPath);
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
        buffer = lines.pop(); // keep last incomplete chunk

        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            const msg = JSON.parse(line.trim());
            this.handleAxMessage(msg);
          } catch (e) {
            // Ignore non-json logs
          }
        }
      });

      this.child.on('exit', (code) => {
        console.log(`[AX Bridge] ax_observer exited with code ${code}. Respawning in 3s...`);
        setTimeout(() => this.start(), 3000);
      });

      console.log('🟢 Native macOS Accessibility (AXUIElement) Screen UI Observer started.');
    } catch (e) {
      console.error('[AX Bridge] Failed to start ax_observer binary:', e.message);
    }
  }

  handleAxMessage(msg) {
    if (msg.type === 'ax_ready') {
      console.log('[AX Bridge] Native AXUIElement Observer Engine Ready.');
    } else if (msg.type === 'ax_permission_required') {
      console.warn('⚠️ [AX Bridge] Accessibility permission required:', msg.message);
    } else if (msg.type === 'ax_prompt_detected') {
      console.log(`\n🔍 [AX Observer] Detected Screen Prompt in [${msg.appName}]: ${msg.command}`);
      this.activePromptId = msg.id;

      const request = {
        id: msg.id,
        agent: msg.appName || 'AI Agent (Screen Prompt)',
        type: 'command_confirmation',
        title: msg.windowTitle || 'Permission Required',
        command: msg.command,
        description: msg.description,
        risk: msg.risk || 'medium',
        time: new Date().toISOString(),
        options: (msg.buttons || []).map((b) => String(b.index)),
        optionsList: (msg.buttons || []).map((b) => ({
          key: String(b.index),
          label: b.label,
          isPrimary: b.isPrimary,
          isDestructive: b.isDestructive,
        })),
        isAxPrompt: true,
      };

      if (this.detector) {
        this.detector.pendingRequest = request;
      }
      if (this.server) {
        this.server.sendRequest(request);
      }
    } else if (msg.type === 'ax_action_result') {
      console.log(`✨ [AX Observer] Element Press Action: ${msg.result} (Button ${msg.buttonIndex})`);
    }
  }

  handleDecision(requestId, action) {
    if (!this.child || !this.child.stdin || !this.child.stdin.writable) return;

    if (this.activePromptId && requestId === this.activePromptId) {
      let buttonIdx = 1;
      if (action === 'reject' || action === '5') {
        buttonIdx = 2;
      } else if (!isNaN(Number(action))) {
        buttonIdx = Number(action);
      }

      console.log(`[AX Bridge] Forwarding remote decision '${action}' to AXUIElement button #${buttonIdx}...`);
      const cmdPayload = JSON.stringify({
        action: 'press',
        promptId: requestId,
        buttonIndex: buttonIdx,
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

module.exports = AxBridge;
