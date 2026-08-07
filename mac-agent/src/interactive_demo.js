const readline = require('readline');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runInteractiveFlow() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const ask = (query) => new Promise(resolve => rl.question(query, resolve));

  console.log('\n======================================================');
  console.log('🎬 REAL-TIME LIVE DEMO: Codex Agent Interactive Chain');
  console.log('======================================================\n');

  console.log('Codex Agent is analyzing workspace files...');
  await sleep(1500);

  // STEP 1
  console.log('\n[Step 1/3] Codex Agent proposed action:');
  console.log('  npm install lodash');
  console.log('------------------------------------------------------');
  console.log('⏳ Waiting for authorization on your iPhone / Apple Watch...');
  
  const ans1 = await ask('Allow execution of command? (y/n) ');

  if (ans1.trim().toLowerCase() === 'y') {
    console.log('\n✅ [MAC DEMO] Received "Yes" from Mobile Device!');
    console.log('   Executing step 1: npm install lodash...');
    await sleep(2000);
    console.log('   ✓ npm install lodash completed successfully.\n');
  } else {
    console.log('\n❌ [MAC DEMO] Rejected from Mobile Device. Stopping execution.');
    rl.close();
    return;
  }

  // STEP 2
  console.log('Codex Agent is preparing clean build...');
  await sleep(1500);

  console.log('\n[Step 2/3] Codex Agent proposed action:');
  console.log('  rm -rf ./build');
  console.log('------------------------------------------------------');
  console.log('⏳ Waiting for authorization on your iPhone / Apple Watch...');

  const ans2 = await ask('Allow execution of command? (y/n) ');

  if (ans2.trim().toLowerCase() === 'y') {
    console.log('\n✅ [MAC DEMO] Received "Yes" from Mobile Device!');
    console.log('   Executing step 2: rm -rf ./build...');
    await sleep(2000);
    console.log('   ✓ Directory ./build cleaned successfully.\n');
  } else {
    console.log('\n❌ [MAC DEMO] Rejected from Mobile Device. Stopping execution.');
    rl.close();
    return;
  }

  // STEP 3
  console.log('Codex Agent is deploying main branch...');
  await sleep(1500);

  console.log('\n[Step 3/3] Codex Agent proposed action (HIGH RISK):');
  console.log('  git push --force origin main');
  console.log('------------------------------------------------------');
  console.log('⏳ Waiting for authorization on your iPhone / Apple Watch...');

  const ans3 = await ask('Allow execution of command? (y/n) ');

  if (ans3.trim().toLowerCase() === 'y') {
    console.log('\n✅ [MAC DEMO] Received "Yes" from Mobile Device!');
    console.log('   Executing step 3: git push --force origin main...');
    await sleep(2000);
    console.log('   ✓ Remote repository deployed successfully.\n');
    console.log('======================================================');
    console.log('🎉 DEMO COMPLETED: All 3 steps approved remotely via phone!');
    console.log('======================================================\n');
  } else {
    console.log('\n❌ [MAC DEMO] Rejected from Mobile Device. Stopping execution.');
  }

  rl.close();
}

runInteractiveFlow();
