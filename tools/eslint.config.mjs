// ESLint over the joined script (tools/lint.py, make lint): src/js/*.js are not modules but pieces of one function, so
// it is only JavaScript once build.py joins them. The script runs in the browser with three.js loaded before it.
export default [{
  languageOptions: {
    ecmaVersion: 2022, sourceType: 'script',
    globals: Object.fromEntries([
      'window', 'document', 'performance', 'console', 'location', 'navigator', 'history', 'localStorage', 'matchMedia',
      'requestAnimationFrame', 'cancelAnimationFrame', 'setTimeout', 'clearTimeout', 'setInterval', 'clearInterval',
      'getComputedStyle', 'innerWidth', 'innerHeight', 'devicePixelRatio', 'addEventListener', 'URL', 'Blob', 'fetch',
      'Image', 'ResizeObserver', 'queueMicrotask', 'MessageChannel', 'THREE',
    ].map(g => [g, 'readonly'])),
  },
  rules: {
    'no-undef': 'error',
    'no-redeclare': 'error',
    'no-shadow': ['error', { builtinGlobals: false, hoist: 'all' }],
    'no-unused-vars': ['error', { args: 'none', caughtErrors: 'none' }],
  },
}];
