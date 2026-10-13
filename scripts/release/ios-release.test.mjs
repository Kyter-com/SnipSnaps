import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

const script = fileURLToPath(new URL("./ios-release.mjs", import.meta.url));

function runRelease(t, command, args, fail = false) {
  const dir = mkdtempSync(path.join(os.tmpdir(), "snipsnaps-release-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const stub = path.join(dir, "asc");
  const calls = path.join(dir, "calls.jsonl");
  writeFileSync(stub, `#!/usr/bin/env node
import { appendFileSync } from 'node:fs';
appendFileSync(process.env.RELEASE_TEST_CALLS, JSON.stringify(process.argv.slice(2)) + '\\n');
if (process.env.RELEASE_TEST_FAIL === '1') {
  console.error('Build not found');
  process.exit(1);
}
console.log(JSON.stringify(process.argv[3] === 'next-build-number'
  ? { nextBuildNumber: process.argv.includes('MAC_OS') ? '75' : '74' }
  : {}));
`, { mode: 0o700 });
  const env = { ...process.env, ASC_BIN: stub, RELEASE_TEST_CALLS: calls, RELEASE_TEST_FAIL: fail ? "1" : "0" };
  delete env.ASC_OP_ITEM;
  const result = spawnSync(process.execPath, [script, command, ...args], { encoding: "utf8", env });
  return {
    ...result,
    calls: () => readFileSync(calls, "utf8").trim().split("\n").map(JSON.parse),
  };
}

function runNotes(t, args, fail = false) {
  return runRelease(t, "apply-notes", ["--target", "testflight", ...args], fail);
}

test("next build considers previous marketing versions on both platforms", (t) => {
  const result = runRelease(t, "next-build", ["--platform", "all"]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Lockstep build number valid across iOS \+ macOS: 75/);
  const calls = result.calls();
  assert.equal(calls.length, 2);
  assert.deepEqual(calls.map((call) => call[call.indexOf("--platform") + 1]), ["IOS", "MAC_OS"]);
  for (const call of calls) assert.ok(!call.includes("--version"));
});

test("TestFlight notes target each platform's Cloud archive without changing the repo build number", (t) => {
  for (const [platform, number] of [["IOS", "74"], ["MAC_OS", "75"]]) {
    const result = runNotes(t, ["--platform", platform, "--build-number", number, "--confirm"]);
    assert.equal(result.status, 0, result.stderr);
    const [call] = result.calls();
    assert.deepEqual(call.slice(0, 3), ["builds", "test-notes", "update"]);
    assert.equal(call[call.indexOf("--platform") + 1], platform);
    assert.equal(call[call.indexOf("--build-number") + 1], number);
    assert.ok(call[call.indexOf("--whats-new") + 1].startsWith("• "));
  }
});

test("dry run displays the selected archive", (t) => {
  const result = runNotes(t, ["--platform", "MAC_OS", "--build-number", "75"]);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Build: 75\n/);
});

test("ambiguous or invalid archive selection fails before calling ASC", (t) => {
  for (const args of [
    ["--platform", "all", "--build-number", "75"],
    ["--build-number", "0"],
    ["--build-number"],
  ]) {
    const result = runNotes(t, [...args, "--confirm"]);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /single --platform|positive integer/);
    assert.throws(result.calls, /ENOENT/);
  }
});

test("failure to update and create notes fails the release step", (t) => {
  const result = runNotes(t, ["--platform", "MAC_OS", "--build-number", "75", "--confirm"], true);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Could not update TestFlight notes for macOS build 75/);
  assert.deepEqual(result.calls().map((call) => call[2]), ["update", "create"]);
});
