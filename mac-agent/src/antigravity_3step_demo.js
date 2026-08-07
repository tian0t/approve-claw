const readline = require('readline');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runAntigravityDemo() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const ask = (query) => new Promise(resolve => rl.question(query, resolve));

  console.log('\n===============================================================');
  console.log('🚀 ANTIGRAVITY IDE AGENT INTERACTIVE DEMO (3 STEPS ONLY)');
  console.log('===============================================================\n');

  console.log('Antigravity IDE Agent is analyzing workspace dependencies...');
  await sleep(1500);

  // -------------------------------------------------------------
  // STEP 1 of 3: Antigravity Low Risk
  // -------------------------------------------------------------
  console.log('\n[Step 1/3] Confirm the command is safe to run outside of the sandbox:');
  console.log('  node -c pages/home/home.js');
  console.log('---------------------------------------------------------------');
  console.log('1 Yes, allow this time');
  console.log('2 Yes, and always allow "node -c pages/home/home.js" in this conversation');
  console.log('5 No (tell the agent what to do instead)');
  console.log('---------------------------------------------------------------');
  console.log('⏳ Waiting for authorization on your iPhone / Apple Watch...');

  const ans1 = await ask('\nSelect choice [1-5]: ');

  if (ans1.trim() === '1' || ans1.trim().toLowerCase() === 'y') {
    console.log('\n✅ [Antigravity IDE] Choice 1 Received from iPhone!');
    console.log('   Executing step 1: node -c pages/home/home.js...');
    await sleep(2000);
    console.log('   ✓ Syntax check passed.\n');
  } else {
    console.log('\n❌ [Antigravity IDE] Rejected from Mobile Device.');
    rl.close();
    return;
  }

  // -------------------------------------------------------------
  // STEP 2 of 3: Antigravity Medium Risk
  // -------------------------------------------------------------
  console.log('Antigravity IDE Agent is building production assets...');
  await sleep(1500);

  console.log('\n[Step 2/3] Confirm the command is safe to run outside of the sandbox:');
  console.log('  npx vite build');
  console.log('---------------------------------------------------------------');
  console.log('1 Yes, allow this time');
  console.log('2 Yes, and always allow "npx vite build" in this conversation');
  console.log('5 No (tell the agent what to do instead)');
  console.log('---------------------------------------------------------------');
  console.log('⏳ Waiting for authorization on your iPhone / Apple Watch...');

  const ans2 = await ask('\nSelect choice [1-5]: ');

  if (ans2.trim() === '1' || ans2.trim().toLowerCase() === 'y') {
    console.log('\n✅ [Antigravity IDE] Choice 1 Received from iPhone!');
    console.log('   Executing step 2: npx vite build...');
    await sleep(2000);
    console.log('   ✓ Bundle created successfully in ./dist.\n');
  } else {
    console.log('\n❌ [Antigravity IDE] Rejected from Mobile Device.');
    rl.close();
    return;
  }

  // -------------------------------------------------------------
  // STEP 3 of 3: Antigravity High Risk
  // -------------------------------------------------------------
  console.log('Antigravity IDE Agent is preparing deployment script...');
  await sleep(1500);

  console.log('\n[Step 3/3] Confirm the command is safe to run (HIGH RISK):');
  console.log('  rm -rf ./dist && chmod +x ./scripts/deploy.sh');
  console.log('---------------------------------------------------------------');
  console.log('1 Yes, allow this time');
  console.log('2 Yes, and always allow "rm -rf ./dist..." in this conversation');
  console.log('5 No (tell the agent what to do instead)');
  console.log('---------------------------------------------------------------');
  console.log('⏳ Waiting for authorization on your iPhone / Apple Watch...');

  const ans3 = await ask('\nSelect choice [1-5]: ');

  if (ans3.trim() === '1' || ans3.trim().toLowerCase() === 'y') {
    console.log('\n✅ [Antigravity IDE] Choice 1 Received from iPhone!');
    console.log('   Executing step 3: rm -rf ./dist && chmod +x ./scripts/deploy.sh...');
    await sleep(2000);
    console.log('   ✓ Deployment environment prepared.\n');
    console.log('===============================================================');
    console.log('🎉 TEST SUCCEEDED: All 3 Antigravity commands approved remotely!');
    console.log('===============================================================\n');
  } else {
    console.log('\n❌ [Antigravity IDE] Rejected from Mobile Device.');
  }

  rl.close();
}

runAntigravityDemo();
