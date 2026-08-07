const fs = require('fs');
const path = require('path');

class RequestLifecycleManager {
  constructor({ timeoutMs = 30000, perAgentQueueLimit = 20, onActivate, onResolve, eventLogPath }) {
    this.timeoutMs = timeoutMs;
    this.perAgentQueueLimit = perAgentQueueLimit;
    this.onActivate = onActivate || (() => {});
    this.onResolve = onResolve || (() => {});
    this.eventLogPath = eventLogPath || path.join(__dirname, '../events.jsonl');

    this.activeById = new Map();
    this.activeByAgent = new Map();
    this.queueByAgent = new Map();
  }

  enqueue(request) {
    const agent = request.agent || 'AI Agent';
    const activeId = this.activeByAgent.get(agent);

    this.logEvent(request.id, 'detected', { agent, risk: request.risk || 'medium' });

    if (!activeId) {
      this.activate(request);
      return { status: 'activated' };
    }

    const queue = this.queueByAgent.get(agent) || [];
    if (queue.length >= this.perAgentQueueLimit) {
      this.logEvent(request.id, 'queue_overflow_rejected', { agent, reason: 'per_agent_queue_limit_reached' });
      return { status: 'overflow' };
    }

    queue.push(request);
    this.queueByAgent.set(agent, queue);
    this.logEvent(request.id, 'enqueued', { agent, queueLength: queue.length });
    return { status: 'enqueued', queueLength: queue.length };
  }

  activate(request) {
    const agent = request.agent || 'AI Agent';
    const timer = setTimeout(() => {
      this.resolve(request.id, {
        selectedOptionKey: this.defaultRejectKey(request),
        action: 'reject',
        reason: 'timeout',
        source: 'system',
      });
    }, this.timeoutMs);
    if (timer.unref) {
      timer.unref();
    }

    this.activeById.set(request.id, { request, timer, settled: false });
    this.activeByAgent.set(agent, request.id);
    this.logEvent(request.id, 'delivered', { agent });
    this.onActivate(request);
  }

  resolve(requestId, decision) {
    const state = this.activeById.get(requestId);
    if (!state || state.settled) {
      return { status: 'ignored' };
    }

    state.settled = true;
    clearTimeout(state.timer);
    this.activeById.delete(requestId);
    this.activeByAgent.delete(state.request.agent || 'AI Agent');

    const resolved = {
      request: state.request,
      selectedOptionKey: decision.selectedOptionKey,
      action: decision.action,
      reason: decision.reason || 'user_decision',
      source: decision.source || 'client',
    };

    if (resolved.reason === 'timeout') {
      this.logEvent(requestId, 'timeout_rejected', { agent: state.request.agent || 'AI Agent' });
    } else {
      this.logEvent(requestId, 'decided', {
        agent: state.request.agent || 'AI Agent',
        selectedOptionKey: resolved.selectedOptionKey,
        action: resolved.action,
        source: resolved.source,
      });
    }

    this.onResolve(resolved);
    this.activateNext(state.request.agent || 'AI Agent');
    return { status: 'resolved', decision: resolved };
  }

  activateNext(agent) {
    const queue = this.queueByAgent.get(agent) || [];
    if (queue.length === 0) {
      return;
    }

    const next = queue.shift();
    this.queueByAgent.set(agent, queue);
    this.activate(next);
  }

  getActiveRequest(requestId) {
    return this.activeById.get(requestId)?.request || null;
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
    this.queueByAgent.clear();
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
