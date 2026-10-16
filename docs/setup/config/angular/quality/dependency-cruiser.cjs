const fs = require('node:fs');

const featureRoot = 'src/app/features';
const featureRoots = fs.existsSync(featureRoot)
  ? fs.readdirSync(featureRoot, { withFileTypes: true }).filter((entry) => entry.isDirectory()).map((entry) => entry.name)
  : [];

const featureBoundaryRules = featureRoots.flatMap((fromFeature) =>
  featureRoots
    .filter((toFeature) => toFeature !== fromFeature)
    .map((toFeature) => ({
      name: `feature-${fromFeature}-must-not-import-${toFeature}`,
      severity: 'error',
      from: { path: `^src/app/features/${fromFeature}/` },
      to: { path: `^src/app/features/${toFeature}/` },
    })),
);

/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    { name: 'no-circular', severity: 'error', from: {}, to: { circular: true } },
    {
      name: 'no-prod-to-spec',
      severity: 'error',
      from: { path: '^src/', pathNot: '\\.(spec|test)\\.ts$' },
      to: { path: '\\.(spec|test)\\.ts$' },
    },
    {
      name: 'no-prod-to-testing-support',
      severity: 'error',
      from: { path: '^src/', pathNot: ['\\.(spec|test)\\.ts$', '^src/app/spec/'] },
      to: { path: '^src/app/spec/' },
    },
    {
      name: 'shared-not-to-features',
      severity: 'error',
      from: { path: '^src/app/shared/' },
      to: { path: '^src/app/features/' },
    },
    {
      name: 'core-not-to-features',
      severity: 'error',
      from: { path: '^src/app/core/' },
      to: { path: '^src/app/features/' },
    },
    {
      name: 'presentation-must-not-import-data-access',
      severity: 'error',
      from: { path: '\\.(component|page)\\.ts$', pathNot: '\\.(spec|test)\\.ts$' },
      to: { path: '^src/app/core/data-access/' },
    },
    ...featureBoundaryRules,
    {
      name: 'http-client-only-in-bootstrap-auth-or-data-access',
      severity: 'error',
      from: {
        path: '^src/app/',
        pathNot: ['^src/app/app\\.config\\.ts$', '^src/app/core/auth/', '^src/app/core/data-access/', '\\.(spec|test)\\.ts$'],
      },
      to: { path: '^node_modules/@angular/common/fesm\\d+/http\\.mjs$' },
    },
    {
      name: 'dynamic-imports-only-in-routes-or-tests',
      severity: 'error',
      from: { pathNot: ['\\.routes\\.ts$', '\\.(spec|test|spec-suite|spec-helpers)\\.ts$'] },
      to: { dynamic: true },
    },
    {
      name: 'avoid-deep-relative-imports',
      severity: 'error',
      from: { path: '^(src/[^/]+/[^/]+/[^/]+/[^/]+/)[^/]+\\.ts$' },
      to: { pathNot: '^$1[^/]+\\.ts$', dependencyTypes: ['local'], dependencyTypesNot: ['aliased'] },
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    exclude: { path: ['^dist/', '^coverage/', '^playwright-report/', '^test-results/', '^\\.angular/'] },
    includeOnly: '^src/',
    tsPreCompilationDeps: true,
    tsConfig: { fileName: 'tsconfig.json' },
  },
};
