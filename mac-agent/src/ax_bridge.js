const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

class AxBridge {
  constructor(server, detector, fallbackBridge = null) {
    this.server = server;
    this.detector = detector;
    this.fallbackBridge = fallbackBridge;
    this.child = null;
    this.binaryPath = path.join(__dirname, '../bin/ax_observer');
    this.activePromptId = null;
    this.activeRequest = null;
    this.pendingDispatches = new Map();

    // Attach decision listener to WebSocket server
    if (this.server) {
      const originalOnDecision = this.server.onDecision;
      this.server.onDecision = (requestId, action, meta = {}) => {
        if (originalOnDecision) {
          originalOnDecision(requestId, action, meta);
        }
        this.handleDecision(requestId, meta.selectedOptionKey || action);
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
      console.log(`\n[AX Observer] Detected Screen Prompt in [${msg.appName}]: ${msg.command}`);

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
      this.activeRequest = request;
      if (this.server) {
        const status = this.server.sendRequest(request);
        if (status === 'activated') {
          this.activePromptId = msg.id;
        }
      }
    } else if (msg.type === 'ax_action_result') {
      console.log(`✨ [AX Observer] Element Press Action: ${msg.result} (Button ${msg.buttonIndex})`);
      const first = this.pendingDispatches.entries().next().value;
      if (!first) return;
      const [id, meta] = first;
      this.pendingDispatches.delete(id);
      if (msg.result !== 'success' && this.fallbackBridge) {
        console.warn(`[AX Bridge] AX press failed; falling back to Vision coordinates for ${id}.`);
        this.fallbackBridge.dispatchFallback(id, meta.action, meta.selectedOptionKey);
        return;
      }
      if (this.server) {
        this.server.broadcast({ type: 'confirmation_completed', id, action: meta.action, selectedOptionKey: meta.selectedOptionKey, reason: null });
      }
    }
  }

  handleDecision(requestId, decisionKey) {
    if (!this.child || !this.child.stdin || !this.child.stdin.writable) return;
    if (requestId !== this.activePromptId) return;

    const options = (this.activeRequest && this.activeRequest.optionsList) || [];
    let buttonIdx;
    if (decisionKey === 'approve') {
      const primary = options.find((o) => o.isPrimary);
      buttonIdx = primary ? Number(primary.key) : 1;
    } else if (decisionKey === 'reject') {
      const destructive = options.find((o) => o.isDestructive);
      buttonIdx = destructive ? Number(destructive.key) : (options.length > 0 ? Number(options[options.length - 1].key) : 2);
    } else {
      buttonIdx = Number(decisionKey);
    }

    if (!Number.isInteger(buttonIdx) || buttonIdx < 1) {
      console.error(`[AX Bridge] Cannot resolve button index for decision '${decisionKey}'.`);
      return;
    }

    console.log(`[AX Bridge] Forwarding remote decision '${decisionKey}' to AXUIElement button #${buttonIdx}...`);
    const cmdPayload = JSON.stringify({
      action: 'press',
      promptId: requestId,
      buttonIndex: buttonIdx,
    });

    this.pendingDispatches.set(requestId, { action: decisionKey, selectedOptionKey: decisionKey });
    this.child.stdin.write(`${cmdPayload}\n`);
    this.activePromptId = null;
    this.activeRequest = null;
  }

  stop() {
    if (this.child) {
      this.child.kill();
    }
  }
}

module.exports = AxBridge;
