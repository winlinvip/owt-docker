
// node-gyp configure && node-gyp build && node index.js
const addon = require('./build/Release/addon');
console.log('[Debug] ' + addon.hello());

