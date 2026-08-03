const pty = require('node-pty');

console.log('Current CWD:', process.cwd());
console.log('Shell Env:', process.env.SHELL);

try {
  console.log('\n--- Test 4: Minimal spawn of zsh (no options at all) ---');
  const p4 = pty.spawn('/bin/zsh', [], {});
  p4.onData(data => console.log('Test 4 Output:', data.trim()));
  console.log('Test 4 Succeeded!');
  p4.kill();
} catch (e) {
  console.error('Test 4 Failed:', e.message);
}

try {
  console.log('\n--- Test 5: Spawn zsh with only name option ---');
  const p5 = pty.spawn('/bin/zsh', [], { name: 'xterm-color' });
  p5.onData(data => console.log('Test 5 Output:', data.trim()));
  console.log('Test 5 Succeeded!');
  p5.kill();
} catch (e) {
  console.error('Test 5 Failed:', e.message);
}

try {
  console.log('\n--- Test 6: Spawn zsh with empty env ---');
  const p6 = pty.spawn('/bin/zsh', [], { env: {} });
  p6.onData(data => console.log('Test 6 Output:', data.trim()));
  console.log('Test 6 Succeeded!');
  p6.kill();
} catch (e) {
  console.error('Test 6 Failed:', e.message);
}
