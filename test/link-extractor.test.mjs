import test from 'node:test';
import assert from 'node:assert/strict';
import { extractEntries } from '../dist/link-extractor.js';

test('extractEntries preserves titles and order', () => {
  const input = `
Módulo 1
1. Introdução https://www.youtube.com/watch?v=mCC0_8eMUKw
2. O que é ABA? https://www.youtube.com/watch?v=uf8Ip45cqqQ
3. Práticas baseadas em evidência https://www.youtube.com/watch?v=E376uIdS1Q8
`;

  const entries = extractEntries(input);

  assert.equal(entries.length, 3);
  assert.equal(entries[0].title, 'Introdução');
  assert.equal(entries[0].url, 'https://www.youtube.com/watch?v=mCC0_8eMUKw');
  assert.equal(entries[1].title, 'O que é ABA?');
  assert.equal(entries[2].title, 'Práticas baseadas em evidência');
});
