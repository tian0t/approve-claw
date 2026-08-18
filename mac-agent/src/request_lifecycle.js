const fs = require('fs');
const path = require('path');

/**
 * Builds a stable semantic signature for a request. Two detections of the
 * same on-screen dialog share a signature even when their ids or raw screen
 * text differ, which lets the lifecycle collapse duplicate cards.
 */
function signatureOf(request) {
  const options = (request.optionsList || []).map((o) => String(o.key)).sort().join(',');
  const command = String(request.command || '').trim().toLowerCase();
  return `${request.agent || 'AI Agent'}|${command}|${options}`;
}

/**
 * Tracks at most ONE active request per agent, matching the reality of a
 * screen-based detector: a single dialog is visible per app at any moment.
 *
 * - Duplicate detections (same signature) are dropped.
 * - A new dialog for an agent retires the previous one without dispatching
 *   anything to the desktop app (the old dialog is already gone from screen).
 * - Timeout clears the phone card only; the desktop prompt is left untouched.
 */
class RequestLifecycleManager {
  constructor({ timeoutMs = 30000, onActivate, onResolve, eventLogPath }) {
    this.timeoutMs = timeoutMs;
    this.onActivate = onActivate || (() => {});
    this.onResolve = onResolve || (() => {});
    this.eventLogPath = eventLogPath || path.join(__dirname, '../events.jsonl');

    this.activeById = new Map();
    this.activeByAgent = new Map();
  }

  enqueue(request) {
    const agent = request.agent || 'AI Agent';
    const signature = signatureOf(request);
    this.logEvent(request.id, 'detected', { agent, risk: request.risk || 'medium' });

    const activeId = this.activeByAgent.get(agent);
    if (activeId) {
      const active = this.activeById.get(activeId);
      if (active) {
        // Prefer AX detections over Vision OCR for the same dialog: AX press
        // acts on the live element, which is safer than coordinate clicks.
        if (active.request.isAxPrompt && request.isVisionPrompt) {
          this.logEvent(request.id, 'duplicate_dropped', { agent, duplicateOf: activeId, reason: 'ax_priority' });
          return { status: 'duplicate' };
        }
        if (active.signature === signature) {
          this.logEvent(request.id, 'duplicate_dropped', { agent, duplicateOf: activeId, reason: 'same_signature' });
          return { status: 'duplicate' };
        }
        // The screen now shows a new dialog for this agent. Retire the old
        // request without dispatching: its coordinates/buttons are stale.
        this.resolve(activeId, {
          action: 'clear',
          reason: 'superseded',
          source: 'system',
          dispatch: false,
        });
      }
    }

    this.activate(request, signature);
    return { status: 'activated' };
  }

  activate(request, signature) {
    const agent = request.agent || 'AI Agent';
    const timer = setTimeout(() => {
      this.resolve(request.id, {
        action: 'clear',
        reason: 'timeout',
        source: 'system',
        dispatch: false,
      });
    }, this.timeoutMs);
    if (timer.unref) {
      timer.unref();
    }

    this.activeById.set(request.id, { request, signature, timer });
    this.activeByAgent.set(agent, request.id);
    this.logEvent(request.id, 'delivered', { agent });
    this.onActivate(request);
  }

  resolve(requestId, decision) {
    const state = this.activeById.get(requestId);
    if (!state) {
      return { status: 'ignored' };
    }

    clearTimeout(state.timer);
    this.activeById.delete(requestId);
    this.activeByAgent.delete(state.request.agent || 'AI Agent');

    const resolved = {
      request: state.request,
      selectedOptionKey: decision.selectedOptionKey || null,
      action: decision.action || 'clear',
      reason: decision.reason || 'user_decision',
      source: decision.source || 'client',
      dispatch: decision.dispatch !== false,
    };

    if (resolved.reason === 'timeout') {
      this.logEvent(requestId, 'timeout_cleared', { agent: state.request.agent || 'AI Agent' });
    } else if (resolved.reason === 'superseded') {
      this.logEvent(requestId, 'superseded_cleared', { agent: state.request.agent || 'AI Agent' });
    } else if (resolved.reason === 'cancelled') {
      this.logEvent(requestId, 'cancelled', { agent: state.request.agent || 'AI Agent' });
    } else {
      this.logEvent(requestId, 'decided', {
        agent: state.request.agent || 'AI Agent',
        selectedOptionKey: resolved.selectedOptionKey,
        action: resolved.action,
        source: resolved.source,
      });
    }

    this.onResolve(resolved);
    return { status: 'resolved', decision: resolved };
  }

  getActiveRequest(requestId) {
    return this.activeById.get(requestId)?.request || null;
  }

  listActiveRequests() {
    return Array.from(this.activeById.values()).map((s) => s.request);
  }

  defaultRejectKey(request) {
    const optionsList = request.optionsList || [];
    const destructive = optionsList.find((opt) => opt.isDestructive);
    if (destructive && destructive.key) {
      return String(destructive.key);
    }
    if ((request.options || []).includes('reject')) {
      return 'reject';
    }
    return 'reject';
  }

  defaultApproveKey(request) {
    const optionsList = request.optionsList || [];
    const primary = optionsList.find((opt) => opt.isPrimary);
    if (primary && primary.key) {
      return String(primary.key);
    }
    if ((request.options || []).includes('approve')) {
      return 'approve';
    }
    return 'approve';
  }

  mapLegacyAction(request, action) {
    if (action === 'approve') {
      return this.defaultApproveKey(request);
    }
    return this.defaultRejectKey(request);
  }

  close() {
    for (const { timer } of this.activeById.values()) {
      clearTimeout(timer);
    }
    this.activeById.clear();
    this.activeByAgent.clear();
  }

  logEvent(requestId, type, data = {}) {
    const record = JSON.stringify({
      timestamp: new Date().toISOString(),
      requestId,
      type,
      ...data,
    });
    try {
      fs.appendFileSync(this.eventLogPath, `${record}\n`);
    } catch (e) {
      // keep runtime resilient even if local log file is not writable
    }
  }
}

module.exports = RequestLifecycleManager;
module.exports.signatureOf = signatureOf;
