// pa11y-ci configuration.
//
// Port is read from PORT (defaults to 1313) so this works with any dev
// server — useful when the dev script picks an alternate free port:
//
//   PORT=1314 npm run pa11y
//   docker compose exec -e PORT=1314 hugo npm run pa11y
const port = process.env.PORT || 1313;
const base = `http://localhost:${port}`;

// The screens to check (WCAG 2.1 AAA). Add screens here as they are built. An
// entry can be a plain path or an object ({ url, ...overrides }) when a screen
// needs extra pa11y options such as a render `wait`.
const paths = [
  // The home page mounts the Elm app client-side, so wait for it to render
  // before evaluating.
  { url: '/', wait: 1000 },
];

module.exports = {
  defaults: {
    standard: 'WCAG2AAA',
    chromeLaunchConfig: {
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-gpu',
        '--disable-dev-shm-usage',
      ],
      protocolTimeout: 60000,
    },
    timeout: 60000,
  },
  urls: paths.map((p) =>
    typeof p === 'string' ? `${base}${p}` : { ...p, url: `${base}${p.url}` }
  ),
};
