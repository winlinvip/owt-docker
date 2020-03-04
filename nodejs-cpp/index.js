
// node-gyp --debug configure build && node index.js
const addon = require('./build/Debug/addon');
console.log('[Debug] ' + addon.hello());

