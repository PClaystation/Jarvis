const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");

const ROOT = process.cwd();
const TEST_ROOT = path.join(ROOT, "test");

function collectTestFiles(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      files.push(...collectTestFiles(fullPath));
      continue;
    }

    if (entry.isFile() && entry.name.endsWith(".test.ts")) {
      files.push(fullPath);
    }
  }

  return files;
}

if (!fs.existsSync(TEST_ROOT)) {
  console.error("No test directory found at ./test");
  process.exit(1);
}

const testFiles = collectTestFiles(TEST_ROOT).sort();

if (testFiles.length === 0) {
  console.error("No test files matched ./test/**/*.test.ts");
  process.exit(1);
}

const args = ["--test", "--import", "tsx", ...testFiles];
const child = spawn(process.execPath, args, { stdio: "inherit" });

child.on("exit", (code, signal) => {
  if (signal) {
    process.kill(process.pid, signal);
    return;
  }

  process.exit(code ?? 1);
});

