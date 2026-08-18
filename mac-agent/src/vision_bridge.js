const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

/**
 * VisionBridge v2.0
 *
 * Responsibilities:
 * - Spawn the native vision_observer binary
 * - Forward vision_prompt_detected events to the WebSocket server (deduplicated)
 * - Route mobile decisions back to vision_observer via stdin
 * - Track ONE active prompt at a time — ignore new detections while one is pending
 */
class VisionBridge {
  constructor(server) {
    this.server = server;
    this.child = null;
    this.binaryPath = path.join(__dirname, '../bin/vision_observer');
    this.activePromptId = null;
    this.pendingPromptIds = new Set(); // IDs dispatched but not yet resolved

    if (this.server) {
      // Hook into server decisions
      const originalOnDecision = this.server.onDecision;
      this.server.onDecision = (requestId, action, meta) => {
        if (originalOnDecision) originalOnDecision(requestId, action, meta);
        this.handleDecision(requestId, action, meta);
      };
    }
  }

  start() {
    if (!fs.existsSync(this.binaryPath)) {
      console.warn('[Vision Bridge] vision_observer binary not found at:', this.binaryPath);
      console.warn('[Vision Bridge] Run: npm run build:vision');
      return;
    }

    this.child = spawn(this.binaryPath, [], { stdio: ['pipe', 'pipe', 'inherit'] });

    let buffer = '';
    this.child.stdout.on('data', (chunk) => {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop(); // keep incomplete last line
      for (const line of lines) {
        if (!line.trim()) continue;
        try {
          const msg = JSON.parse(line.trim());
          this.handleVisionMessage(msg);
        } catch (_) { /* non-JSON line — ignore */ }
      }
    });

    this.child.on('exit', (code) => {
      console.log(`[Vision Bridge] vision_observer exited (code=${code}). Restarting in 3s…`);
      this.activePromptId = null;
      setTimeout(() => this.start(), 3000);
    });

    console.log('👁️  Universal Apple Vision OCR Screen Observer started.');
  }

  handleVisionMessage(msg) {
    switch (msg.type) {
      case 'vision_ready':
        console.log('[Vision Bridge] Native Vision Engine is active and scanning screen.');
        break;

      case 'vision_prompt_detected': {
        // If there is already an active (unresolved) prompt, skip this new detection.
        // This prevents the iOS app from being flooded with duplicate cards.
        if (this.activePromptId && this.pendingPromptIds.has(this.activePromptId)) {
          return;
        }

        this.activePromptId = msg.id;
        this.pendingPromptIds.add(msg.id);

        const request = {
          id: msg.id,
          agent: msg.agent || 'AI Agent',
          type: 'command_confirmation',
          title: msg.title || `${msg.agent} Permission Required`,
          command: msg.command || 'Tool Execution',
          description: msg.description || 'Detected on screen — choose how to respond:',
          risk: msg.risk || 'medium',
          time: new Date().toISOString(),
          options: msg.options || ['1', '5'],
          optionsList: msg.optionsList || [
            { key: '1', label: '1. Yes, allow this time', isPrimary: true, isDestructive: false },
            { key: '5', label: '5. No (Deny)', isPrimary: false, isDestructive: true },
          ],
          isVisionPrompt: true,
        };

        console.log(`\n👁️  [Vision OCR] Prompt detected on screen:`);
        console.log(`    Agent:   ${request.agent}`);
        console.log(`    Command: ${request.command}`);
        console.log(`    Risk:    ${request.risk.toUpperCase()}`);
        console.log(`    Options: ${request.optionsList.map(o => o.key).join(', ')}`);

        if (this.server) {
          this.server.sendRequest(request);
        }
        break;
      }

      case 'prompt_cleared':
        console.log('[Vision OCR] Screen prompt cleared (agent resumed).');
        if (this.activePromptId) {
          this.pendingPromptIds.delete(this.activePromptId);
          this.activePromptId = null;
        }
        break;

      case 'keystroke_dispatched':
        console.log(`✨ [Keystroke] '${msg.sent || msg.action}' sent to Mac terminal.`);
        break;

      default:
        break;
    }
  }

  handleDecision(requestId, action, meta) {
    if (!this.child?.stdin?.writable) return;
    if (requestId !== this.activePromptId) return;

    // Resolve the option key: prefer selectedOptionKey from meta, fall back to action
    const selectedKey = (meta && meta.selectedOptionKey) ? meta.selectedOptionKey : action;

    console.log(`[Vision Bridge] Mobile decision '${selectedKey}' → dispatching keystroke…`);

    const cmdPayload = JSON.stringify({ action: selectedKey, promptId: requestId });
    this.child.stdin.write(`${cmdPayload}\n`);

    // Mark this prompt as resolved
    this.pendingPromptIds.delete(requestId);
    this.activePromptId = null;

    // Tell the iOS app the request is done
    if (this.server) {
      this.server.broadcastCleared(requestId);
    }
  }

  stop() {
    if (this.child) {
      this.child.kill('SIGTERM');
      this.child = null;
    }
  }
}

module.exports = VisionBridge;
