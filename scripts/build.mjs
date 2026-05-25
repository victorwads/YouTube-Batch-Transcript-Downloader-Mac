import { mkdir, rm, copyFile, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const rootDir = fileURLToPath(new URL('..', import.meta.url));
const distDir = join(rootDir, 'dist');
const srcDir = join(rootDir, 'src');

await rm(distDir, { recursive: true, force: true });
await mkdir(distDir, { recursive: true });

execFileSync('npx', ['tsc', '-p', 'tsconfig.main.json'], {
  cwd: rootDir,
  stdio: 'inherit',
});

execFileSync('npx', ['tsc', '-p', 'tsconfig.renderer.json'], {
  cwd: rootDir,
  stdio: 'inherit',
});

await copyFile(join(srcDir, 'index.html'), join(distDir, 'index.html'));
await copyFile(join(srcDir, 'styles.css'), join(distDir, 'styles.css'));
