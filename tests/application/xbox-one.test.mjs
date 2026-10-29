import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';

let server;
let categories;
let types;
let suggestions;
let csv;
let covers;

before(async () => {
  server = await createServer({
    configFile: false,
    optimizeDeps: { noDiscovery: true, include: [] },
    resolve: {
      alias: { '@': fileURLToPath(new URL('../../src', import.meta.url)) },
    },
    server: { middlewareMode: true },
  });
  [categories, types, suggestions, csv, covers] = await Promise.all([
    server.ssrLoadModule('/src/lib/categories.ts'),
    server.ssrLoadModule('/src/lib/types.ts'),
    server.ssrLoadModule('/src/lib/platform-suggestions.ts'),
    server.ssrLoadModule('/src/lib/csv.ts'),
    server.ssrLoadModule('/src/lib/covers.ts'),
  ]);
});

after(async () => {
  await server?.close();
});

test('Xbox One is a separate default platform from the original Xbox', () => {
  const xboxOne = categories.DEFAULT_CATEGORIES.filter(category => category.id === 'XBOXONE');
  assert.equal(xboxOne.length, 1);
  assert.deepEqual(xboxOne[0], categories.XBOX_ONE_CATEGORY);
  assert.equal(xboxOne[0].name, types.PLATFORM_NAMES.XBOXONE);
  assert.equal(xboxOne[0].logoUrl, types.PLATFORM_LOGOS.XBOXONE);
  assert.equal(categories.DEFAULT_CATEGORIES.find(category => category.id === 'XBOX').name, 'Xbox');
});

test('Xbox One has exactly three unique suggestions, not saved game records', () => {
  const platformSuggestions = suggestions.PLATFORM_SUGGESTIONS.XBOXONE;
  const titles = [...platformSuggestions.topRated, ...platformSuggestions.mostCollectible];
  assert.deepEqual(titles, [
    'Halo: The Master Chief Collection',
    'Forza Horizon 4',
    'Gears 5',
  ]);
  assert.equal(new Set(titles).size, 3);
  assert.ok(titles.every(title => typeof title === 'string'));
});

test('CSV round-trips Xbox One games without changing ownership or original Xbox', () => {
  const games = [
    { id: 'one', name: 'Xbox One example', platform: 'XBOXONE', acquired: false },
    { id: 'original', name: 'Xbox example', platform: 'XBOX', acquired: true },
  ];
  const parsed = csv.parseCSV(
    csv.exportGamesToCSV(games),
    categories.DEFAULT_CATEGORIES.map(category => category.id),
  );
  assert.deepEqual(parsed.errors, []);
  assert.deepEqual(
    parsed.games.map(({ name, platform, acquired }) => ({ name, platform, acquired })),
    games.map(({ name, platform, acquired }) => ({ name, platform, acquired })),
  );
});

test('Xbox One uses placeholder covers without affecting supported serial lookups', () => {
  assert.equal(covers.buildCoverUrl('XBOXONE', 'EXAMPLE'), null);
  assert.equal(covers.buildCoverUrl('PS1', 'sces00001'),
    'https://raw.githubusercontent.com/xlenore/psx-covers/main/covers/default/SCES-00001.jpg');
});
