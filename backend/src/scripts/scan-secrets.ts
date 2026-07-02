import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = execFileSync('git', ['rev-parse', '--show-toplevel'], {
  encoding: 'utf8',
}).trim();

const files = execFileSync('git', ['ls-files'], {
  cwd: root,
  encoding: 'utf8',
})
  .split('\n')
  .filter(Boolean)
  .filter((file) => !file.endsWith('.lock'))
  .filter((file) => !file.includes('/dist/'));

const patterns = [
  { name: 'private key', regex: /-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----/ },
  { name: 'GitHub token', regex: /\bgh[pousr]_[A-Za-z0-9_]{36,}\b/ },
  { name: 'AWS access key', regex: /\bAKIA[0-9A-Z]{16}\b/ },
  { name: 'AWS secret key assignment', regex: /aws(.{0,20})?(secret|private).{0,20}=\s*['"]?[A-Za-z0-9/+]{40}['"]?/i },
  { name: 'Slack token', regex: /\bxox[baprs]-[A-Za-z0-9-]{20,}\b/ },
  { name: 'Stripe live key', regex: /\b(?:sk|rk)_live_[A-Za-z0-9]{20,}\b/ },
];

const findings: string[] = [];

for (const file of files) {
  let content = '';
  try {
    content = readFileSync(join(root, file), 'utf8');
  } catch {
    continue;
  }

  for (const pattern of patterns) {
    if (pattern.regex.test(content)) {
      findings.push(`${file}: possible ${pattern.name}`);
    }
  }
}

if (findings.length > 0) {
  console.error('Potential secrets found:\n' + findings.join('\n'));
  process.exit(1);
}

console.log('No high-confidence secret patterns found.');
