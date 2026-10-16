import fs from 'node:fs';
import path from 'node:path';

import angular from '@angular-eslint/eslint-plugin';
import angularTemplate from '@angular-eslint/eslint-plugin-template';
import angularTemplateParser from '@angular-eslint/template-parser';
import eslint from '@eslint/js';
import importX from 'eslint-plugin-import-x';
import stylistic from '@stylistic/eslint-plugin';
import tseslint from 'typescript-eslint';

const projectRoot = process.cwd();
const tsConfig = JSON.parse(
  fs.readFileSync(path.join(projectRoot, 'tsconfig.json'), 'utf8').replaceAll(/\/\*[\s\S]*?\*\//g, ''),
);

const pathAliases = Object.entries(tsConfig.compilerOptions.paths ?? {})
  .filter(([alias]) => alias.endsWith('/*'))
  .map(([alias, targets]) => ({
    aliasPrefix: alias.slice(0, -2),
    targetRoot: normalizePath(path.resolve(projectRoot, targets[0].slice(0, -2))),
  }))
  .sort((left, right) => right.targetRoot.length - left.targetRoot.length);

const featureAliases = Object.keys(tsConfig.compilerOptions.paths ?? {}).filter(
  (alias) =>
    alias.startsWith('@') &&
    !['@core', '@core/*', '@shared', '@shared/*', '@spec', '@spec/*', '@env', '@env/*'].includes(alias),
);

const projectImportPlugin = {
  rules: {
    'single-line-import': {
      meta: {
        type: 'layout',
        fixable: 'whitespace',
        schema: [],
        messages: { singleLine: 'Import-Anweisungen müssen einzeilig bleiben.' },
      },
      create(context) {
        return {
          ImportDeclaration(node) {
            const currentText = context.sourceCode.getText(node);
            const singleLineText = currentText
              .replace(/\s+/g, ' ')
              .replace(/\{\s*/g, '{ ')
              .replace(/,\s*\}/g, ' }')
              .replace(/\s*\}/g, ' }');

            if (currentText !== singleLineText) {
              context.report({
                node,
                messageId: 'singleLine',
                fix:
                  context.sourceCode.getCommentsInside(node).length === 0
                    ? (fixer) => fixer.replaceText(node, singleLineText)
                    : null,
              });
            }
          },
        };
      },
    },
    // Zulässig ist `@Component({ imports: [Accordion, Action] })`, auch mit Component-Alias.
    // Mehrzeilige Listen sind Fehler; Listen mit Kommentaren werden nicht automatisch korrigiert.
    'single-line-component-imports': {
      meta: {
        type: 'layout',
        fixable: 'whitespace',
        schema: [],
        messages: {
          singleLine:
            'Die imports-Liste von @Component muss einzeilig bleiben. Für lange Listen kann // prettier-ignore verwendet werden.',
        },
      },
      create(context) {
        const componentDecoratorNames = new Set();

        return {
          ImportDeclaration(node) {
            if (node.source.value !== '@angular/core') return;

            for (const specifier of node.specifiers) {
              if (specifier.type === 'ImportSpecifier' && specifier.imported.name === 'Component') {
                componentDecoratorNames.add(specifier.local.name);
              }
            }
          },
          Decorator(node) {
            const expression = node.expression;
            if (expression.type !== 'CallExpression' || expression.callee.type !== 'Identifier') return;
            if (!componentDecoratorNames.has(expression.callee.name)) return;

            const componentMetadata = expression.arguments[0];
            if (!componentMetadata || componentMetadata.type !== 'ObjectExpression') return;

            const importsProperty = componentMetadata.properties.find(
              (property) =>
                property.type === 'Property' &&
                !property.computed &&
                ((property.key.type === 'Identifier' && property.key.name === 'imports') ||
                  (property.key.type === 'Literal' && property.key.value === 'imports')),
            );
            if (!importsProperty || importsProperty.value.type !== 'ArrayExpression') return;

            const importsList = importsProperty.value;
            if (importsList.loc.start.line === importsList.loc.end.line) return;

            const currentText = context.sourceCode.getText(importsList);
            const singleLineText = currentText
              .replace(/\s+/g, ' ')
              .replace(/\[\s*/g, '[')
              .replace(/,?\s*\]/g, ']');
            context.report({
              node: importsList,
              messageId: 'singleLine',
              fix:
                context.sourceCode.getCommentsInside(importsList).length === 0
                  ? (fixer) => fixer.replaceText(importsList, singleLineText)
                  : null,
            });
          },
        };
      },
    },
    'prefer-tsconfig-path-alias': {
      meta: {
        type: 'problem',
        fixable: 'code',
        schema: [],
        messages: { preferAlias: 'Nutze den Pfadalias "{{aliasImport}}" statt "{{source}}".' },
      },
      create(context) {
        function checkSource(node) {
          const source = node.source?.value;
          if (typeof source !== 'string' || !source.startsWith('.')) return;
          const resolvedImportPath = normalizePath(path.resolve(path.dirname(context.filename), source));
          const matchingAlias = pathAliases.find(
            ({ targetRoot }) =>
              resolvedImportPath === targetRoot || resolvedImportPath.startsWith(`${targetRoot}/`),
          );
          if (!matchingAlias) return;
          const suffix = resolvedImportPath.slice(matchingAlias.targetRoot.length).replace(/^\//, '');
          const aliasImport = suffix
            ? `${matchingAlias.aliasPrefix}/${suffix}`
            : matchingAlias.aliasPrefix;
          context.report({
            node: node.source,
            messageId: 'preferAlias',
            data: { aliasImport, source },
            fix: (fixer) => fixer.replaceText(node.source, `'${aliasImport}'`),
          });
        }
        return {
          ExportAllDeclaration: checkSource,
          ExportNamedDeclaration: checkSource,
          ImportExpression: checkSource,
          ImportDeclaration: checkSource,
        };
      },
    },
  },
};

function normalizePath(filePath) {
  return filePath.replaceAll('\\', '/');
}

export default tseslint.config(
  { linterOptions: { reportUnusedDisableDirectives: 'error', reportUnusedInlineConfigs: 'error' } },
  {
    ignores: [
      'dist/**',
      'coverage/**',
      'playwright-report/**',
      'test-results/**',
      'node_modules/**',
      '.angular/**',
      '**/.angular/**',
      'dependency-graph.dot',
    ],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.ts'],
    plugins: {
      '@angular-eslint': angular,
      '@stylistic': stylistic,
      projectImport: projectImportPlugin,
      'import-x': importX,
    },
    languageOptions: { parserOptions: { projectService: true, tsconfigRootDir: projectRoot } },
    processor: angularTemplate.processors['extract-inline-html'],
    rules: {
      'no-async-promise-executor': 'error',
      'no-duplicate-imports': ['error', { allowSeparateTypeImports: true }],
      'no-fallthrough': 'error',
      'no-promise-executor-return': 'error',
      'no-unreachable-loop': 'error',
      'prefer-const': 'error',
      eqeqeq: ['error', 'always'],
      'max-lines': ['error', { max: 200, skipBlankLines: true, skipComments: true }],
      'max-lines-per-function': [
        'error',
        { max: 25, IIFEs: true, skipBlankLines: true, skipComments: true },
      ],
      'import-x/no-cycle': 'error',
      'import-x/no-duplicates': 'error',
      'import-x/no-self-import': 'error',
      'import-x/no-useless-path-segments': 'error',
      'projectImport/prefer-tsconfig-path-alias': 'error',
      'projectImport/single-line-import': 'error',
      'projectImport/single-line-component-imports': 'error',
      '@angular-eslint/no-empty-lifecycle-method': 'error',
      '@angular-eslint/no-output-native': 'error',
      '@angular-eslint/no-output-on-prefix': 'error',
      '@angular-eslint/prefer-inject': 'error',
      '@angular-eslint/prefer-on-push-component-change-detection': 'error',
      '@angular-eslint/use-lifecycle-interface': 'error',
      '@typescript-eslint/await-thenable': 'error',
      '@typescript-eslint/consistent-type-imports': 'error',
      '@typescript-eslint/consistent-type-definitions': ['error', 'type'],
      '@typescript-eslint/explicit-function-return-type': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/no-unnecessary-condition': 'error',
      '@typescript-eslint/no-unnecessary-type-assertion': 'error',
      '@typescript-eslint/no-unsafe-argument': 'error',
      '@typescript-eslint/no-unsafe-assignment': 'error',
      '@typescript-eslint/no-unsafe-call': 'error',
      '@typescript-eslint/no-unsafe-member-access': 'error',
      '@typescript-eslint/no-unsafe-return': 'error',
      '@typescript-eslint/only-throw-error': 'error',
      '@typescript-eslint/prefer-promise-reject-errors': 'error',
      '@typescript-eslint/switch-exhaustiveness-check': 'error',
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
          ignoreRestSiblings: true,
        },
      ],
    },
  },
  {
    files: ['src/app/core/**/*.ts', 'src/app/shared/**/*.ts'],
    rules: {
      'no-restricted-imports': [
        'error',
        { patterns: [{ group: featureAliases, message: 'Core und Shared dürfen nicht von Features abhängen.' }] },
      ],
    },
  },
  {
    files: ['**/*.spec.ts'],
    languageOptions: {
      parserOptions: { project: './tsconfig.spec.json', projectService: false, tsconfigRootDir: projectRoot },
    },
    rules: { '@typescript-eslint/no-non-null-assertion': 'off' },
  },
  {
    files: ['**/*.html'],
    languageOptions: { parser: angularTemplateParser },
    plugins: { '@angular-eslint/template': angularTemplate },
    rules: {
      '@angular-eslint/template/alt-text': 'error',
      '@angular-eslint/template/attributes-order': 'error',
      '@angular-eslint/template/banana-in-box': 'error',
      '@angular-eslint/template/button-has-type': 'error',
      '@angular-eslint/template/click-events-have-key-events': 'error',
      '@angular-eslint/template/eqeqeq': 'error',
      '@angular-eslint/template/elements-content': 'error',
      '@angular-eslint/template/interactive-supports-focus': 'error',
      '@angular-eslint/template/label-has-associated-control': 'error',
      '@angular-eslint/template/mouse-events-have-key-events': 'error',
      '@angular-eslint/template/no-autofocus': 'error',
      '@angular-eslint/template/no-distracting-elements': 'error',
      '@angular-eslint/template/no-duplicate-attributes': 'error',
      '@angular-eslint/template/no-empty-control-flow': 'error',
      '@angular-eslint/template/no-inline-styles': 'error',
      '@angular-eslint/template/no-interpolation-in-attributes': 'error',
      '@angular-eslint/template/no-outerhtml': 'error',
      '@angular-eslint/template/no-positive-tabindex': 'error',
      '@angular-eslint/template/prefer-at-empty': 'error',
      '@angular-eslint/template/prefer-built-in-pipes': 'error',
      '@angular-eslint/template/prefer-control-flow': 'error',
      '@angular-eslint/template/prefer-ngsrc': 'error',
      '@angular-eslint/template/prefer-self-closing-tags': 'error',
      '@angular-eslint/template/role-has-required-aria': 'error',
      '@angular-eslint/template/table-scope': 'error',
      '@angular-eslint/template/valid-aria': 'error',
    },
  },
);
