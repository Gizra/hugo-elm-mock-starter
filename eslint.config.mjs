import js from '@eslint/js';
import stylistic from '@stylistic/eslint-plugin-js';
import globals from 'globals';

export default [
  {
    ignores: [
      'node_modules/**',
      'public/**',
      'public-build/**',
      'resources/**',
      'assets/css/node_modules/**',
      'assets/javascript/vendor/**',
    ],
  },
  js.configs.recommended,
  {
    files: ['assets/javascript/**/*.js'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'script',
      globals: {
        ...globals.browser,
      },
    },
    plugins: {
      '@stylistic': stylistic,
    },
    rules: {
      'no-var': 'error',
      'prefer-const': 'error',
      'prefer-arrow-callback': 'error',
      'object-shorthand': ['error', 'always'],
      curly: ['error', 'all'],

      '@stylistic/quotes': ['error', 'single', { avoidEscape: true }],
      '@stylistic/semi': ['error', 'always'],
      '@stylistic/indent': ['error', 2],
      '@stylistic/no-trailing-spaces': 'error',
      '@stylistic/eol-last': 'error',
      '@stylistic/comma-dangle': ['error', 'only-multiline'],
    },
  },
];
