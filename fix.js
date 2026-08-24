const fs = require('fs');
let c = fs.readFileSync('c:/Tokcos/index.html', 'utf8');

// Fix ternary operators where empty string is missing
// Pattern: 'selected':'}>  should be  'selected':''}>
c = c.split("'selected':'}>").join("'selected':''}>");

// Also fix: 'selected':'}  (without >)  
c = c.split("'selected':'}").join("'selected':''}");

fs.writeFileSync('c:/Tokcos/index.html', c, 'utf8');
console.log('Fixed ternary operators');
console.log('File size:', c.length);
