const fs = require('fs');
const path = 'index.html';
const s = fs.readFileSync(path, 'utf8');
const st = s.indexOf('<script>', s.indexOf('supabase-js@2'));
const en = s.indexOf('</script>', st);
fs.writeFileSync('__check.js', s.slice(st + 8, en));
console.log('Extracted:', s.slice(0, st).split('\n').length, 'lines before script');
console.log('Script length:', en - (st + 8));
