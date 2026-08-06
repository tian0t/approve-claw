const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

function askQuestion(query) {
  return new Promise((resolve) => rl.question(query, resolve));
}

async function runMock() {
  console.log('\n=== Start Mock AI Agent ===\n');
  console.log('Task: Set up the project dependencies and clean build directory.');
  console.log('AI Agent is thinking...');
  
  await new Promise(r => setTimeout(r, 1000));
  
  // Test 1: Low-risk command
  console.log('\nClaude Code wants to run the following command:');
  console.log('  npm install lodash');
  const ans1 = await askQuestion('Allow? (y/n) ');
  
  if (ans1.trim().toLowerCase() === 'y') {
    console.log('✓ Command approved. Executing: npm install lodash...');
    await new Promise(r => setTimeout(r, 1500));
    console.log('  lodash installed successfully.');
  } else {
    console.log('✗ Command rejected. Skipping install.');
  }

  await new Promise(r => setTimeout(r, 1000));

  // Test 2: High-risk command
  console.log('\nClaude Code wants to run the following command:');
  console.log('  rm -rf ./build');
  const ans2 = await askQuestion('Allow? (y/n) ');

  if (ans2.trim().toLowerCase() === 'y') {
    console.log('✓ Command approved. Executing: rm -rf ./build...');
    await new Promise(r => setTimeout(r, 1000));
    console.log('  build directory cleaned.');
  } else {
    console.log('✗ Command rejected. Skipping build cleanup.');
  }

  await new Promise(r => setTimeout(r, 1000));

  // Test 3: Codex CLI prompt
  console.log('\nCodex wants to execute:');
  console.log('  git push --force origin main');
  const ans3 = await askQuestion('Allow execution of command? (y/n) ');

  if (ans3.trim().toLowerCase() === 'y') {
    console.log('✓ Codex command approved. Executing git push...');
  } else {
    console.log('✗ Codex command rejected.');
  }

  console.log('\n=== Mock AI Agent Completed ===\n');
  rl.close();
}

runMock();
