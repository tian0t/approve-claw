const fs = require('fs');
const path = require('path');
const exec = require('child_process').exec;
const crypto = require('crypto');

class AntigravityIdeBridge {
  constructor(server, detector) {
    this.server = server;
    this.detector = detector;
    this.brainDir = '/Users/yu./.gemini/antigravity/brain';
    this.lastProcessedSteps = new Map(); // filepath -> lastProcessedStepIndex
    this.processedStepKeys = new Set();  // Set of "filepath_stepIndex"
    this.activePromptStepIndex = -1;
    this.isWatching = false;
    // Current meta conversation ID building CLAW Approve
    this.selfConvId = 'd7245b36-d24e-4576-9b4a-c9c2486467a7';
  }

  start() {
    if (this.isWatching) return;
    this.isWatching = true;
    console.log('🟢 Antigravity IDE Workspace-Only Screen-Mirror Watcher started.');
    
    // Poll brain logs every 400ms
    setInterval(() => {
      this.scanAndCheckLogs();
    }, 400);

    // Register decision handler on server
    const oldHandler = this.server.onDecision;
    this.server.onDecision = (requestId, action) => {
      if (this.detector.pendingRequest && this.detector.pendingRequest.id === requestId) {
        if (this.detector.pendingRequest.isIdePrompt || this.detector.pendingRequest.agent === 'Antigravity IDE') {
          console.log(`\n[CLAW Approve] Forwarding decision '${action}' to Antigravity IDE window via System Events...`);
          this.sendIdeKeypress(action);
          this.detector.acknowledge();
          this.activePromptStepIndex = -1;
          return;
        }
      }
      if (typeof oldHandler === 'function') {
        oldHandler(requestId, action);
      }
    };
  }

  sendIdeKeypress(action) {
    let key = action;
    if (action === 'approve') key = '1';
    if (action === 'reject') key = '5';
    
    // Use osascript to send key '1'-'5' and Return to Google Antigravity IDE
    const script = `
      tell application "System Events"
        if exists (process "Google Antigravity") then
          tell process "Google Antigravity"
            set frontmost to true
            delay 0.1
            keystroke "${key}"
            delay 0.1
            key code 36
          end tell
        end if
      end tell
    `;

    exec(`osascript -e '${script}'`, (error, stdout, stderr) => {
      if (error) {
        console.error('Failed to send keystroke to Antigravity IDE:', error.message);
      } else {
        console.log(`✅ Successfully sent keystroke '${key} + Return' to Google Antigravity IDE!`);
      }
    });
  }

  scanAndCheckLogs() {
    if (!fs.existsSync(this.brainDir)) return;

    try {
      const convDirs = fs.readdirSync(this.brainDir);
      const activeTranscripts = [];

      for (const convId of convDirs) {
        // Exclude the current meta-development conversation (claude-watch)
        if (convId === this.selfConvId) {
          continue;
        }

        const transcriptPath = path.join(this.brainDir, convId, '.system_generated/logs/transcript.jsonl');
        if (fs.existsSync(transcriptPath)) {
          const stats = fs.statSync(transcriptPath);
          // Only check transcripts modified within the last 5 minutes (user active workspace)
          if (Date.now() - stats.mtimeMs < 300000) {
            activeTranscripts.push({ filepath: transcriptPath, mtime: stats.mtimeMs });
          }
        }
      }

      // Sort by MOST RECENTLY MODIFIED user workspace transcript first
      activeTranscripts.sort((a, b) => b.mtime - a.mtime);

      for (const item of activeTranscripts) {
        this.checkTranscript(item.filepath);
      }
    } catch (e) {
      // ignore
    }
  }

  checkTranscript(filepath) {
    try {
      const stats = fs.statSync(filepath);
      if (!stats.isFile()) return;

      const content = fs.readFileSync(filepath, 'utf8');
      const lines = content.split('\n').filter(Boolean);

      const lastStepIndex = this.lastProcessedSteps.get(filepath) || -1;
      let maxSeenIndex = lastStepIndex;

      // Find the last explicit permission request on screen and last action in transcript
      let lastModelToolStepIndex = -1;
      let lastModelToolCall = null;
      let lastActionStepIndex = -1;

      for (let i = 0; i < lines.length; i++) {
        try {
          const entry = JSON.parse(lines[i]);
          const stepIndex = entry.step_index ?? i;

          if (entry.source === 'MODEL' && entry.type === 'PLANNER_RESPONSE' && entry.tool_calls) {
            for (const tool of entry.tool_calls) {
              const toolName = tool.name;
              const args = tool.args || {};

              // STRICTLY MIRROR USER WORKSPACE COMPUTER SCREEN PERMISSION PROMPTS ONLY:
              // 1. ask_permission (e.g. "Allow write access to this path?")
              // 2. run_command with BypassSandbox: true (e.g. "Confirm the command is safe to run outside of the sandbox")
              const isScreenPermissionPrompt = 
                toolName === 'ask_permission' || 
                (toolName === 'run_command' && (args.BypassSandbox === 'true' || args.BypassSandbox === true));

              if (isScreenPermissionPrompt) {
                lastModelToolStepIndex = stepIndex;
                lastModelToolCall = { tool, entry };
              }
            }
          }

          if (entry.source === 'CODE_ACTION' || entry.source === 'USER_EXPLICIT' || entry.type === 'USER_INPUT') {
            lastActionStepIndex = stepIndex;
          }
        } catch (e) {
          // ignore
        }
      }

      // If the permission prompt on Mac was answered or completed, clear pending request on phone/watch
      if (this.detector.pendingRequest && this.detector.pendingRequest.isIdePrompt) {
        if (lastActionStepIndex > lastModelToolStepIndex && lastActionStepIndex > this.activePromptStepIndex) {
          const reqId = this.detector.pendingRequest.id;
          this.detector.acknowledge();
          this.activePromptStepIndex = -1;
          this.server.broadcast({ type: 'confirmation_completed', id: reqId, action: 'approved' });
          console.log(`[CLAW Approve] User workspace permission prompt answered! Auto-cleared pending prompt on phone/watch [${reqId}].`);
        }
      }

      // If there is an UNANSWERED user workspace permission prompt on screen
      if (lastModelToolStepIndex > lastActionStepIndex && lastModelToolCall) {
        const stepKey = `${filepath}_${lastModelToolStepIndex}`;

        if (!this.processedStepKeys.has(stepKey) && !this.detector.pendingRequest) {
          const { tool, entry } = lastModelToolCall;
          const toolName = tool.name;
          const args = tool.args || {};
          let rawCmd = args.CommandLine || args.Target || args.TargetFile || args.Url || toolName;
          rawCmd = String(rawCmd).replace(/^"|"$/g, '').trim();

          let title = `Allow permission in Antigravity IDE?`;
          if (toolName === 'ask_permission') {
            const action = args.Action ? String(args.Action).replace(/^"|"$/g, '') : 'access';
            if (action === 'write_file' || action === 'write') {
              title = `Allow write access to this path?`;
            } else {
              title = `Allow ${action} access to this path?`;
            }
          } else if (toolName === 'run_command') {
            const actionSummary = args.toolSummary || args.toolAction || '';
            if (actionSummary) {
              title = `Allow ${actionSummary.toLowerCase()}?`;
            } else {
              title = `Confirm command safe to run outside sandbox?`;
            }
          }

          const optionsList = [
            { key: '1', label: '1. Yes, allow this time', isPrimary: true, isDestructive: false },
            { key: '2', label: '2. Yes, and always allow in this conversation', isPrimary: false, isDestructive: false },
            { key: '3', label: '3. Yes, and always allow when not in project', isPrimary: false, isDestructive: false },
            { key: '4', label: '4. Yes, and always allow', isPrimary: false, isDestructive: false },
            { key: '5', label: '5. No (tell the agent what to do instead)', isPrimary: false, isDestructive: true }
          ];

          const req = {
            id: 'req_' + crypto.randomBytes(4).toString('hex'),
            agent: 'Antigravity IDE',
            type: 'command_confirmation',
            title: title,
            command: rawCmd,
            description: `Confirm execution/write in Antigravity IDE`,
            risk: this.detector.assessRisk(rawCmd),
            time: new Date().toISOString(),
            options: optionsList.map((o) => o.key),
            optionsList: optionsList,
            isIdePrompt: true
          };

          this.processedStepKeys.add(stepKey);
          this.detector.pendingRequest = req;
          this.activePromptStepIndex = lastModelToolStepIndex;
          this.server.sendRequest(req);
          console.log(`[CLAW Approve] 🎯 Pushed USER WORKSPACE PERMISSION PROMPT [${toolName}] (step: ${lastModelToolStepIndex}) to Watch/iPhone: ${title} -> ${req.command}`);
        }
      }

      this.lastProcessedSteps.set(filepath, maxSeenIndex);
    } catch (e) {
      // ignore
    }
  }
}

module.exports = AntigravityIdeBridge;
