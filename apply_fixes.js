// Clean fix script - reads escapeHtml from file to avoid quoting issues
const fs = require('fs');

let c = fs.readFileSync('c:/Tokcos/index.html', 'utf8');
let escapeHtmlFn = fs.readFileSync('c:/Tokcos/escape_fn.txt', 'utf8').trim();
let changes = [];

function tryReplace(oldStr, newStr, label) {
  if (c.includes(oldStr)) {
    c = c.replace(oldStr, newStr);
    changes.push(label + ': OK');
  } else {
    changes.push(label + ': NOT FOUND');
  }
}

// Fix 1 (completion): renderAdminShell - use classList instead of style.display
tryReplace(
  "document.getElementById('adminLogoutBtn').style.display = 'inline-flex';",
  "document.getElementById('adminLogoutBtn').classList.remove('admin-logout-btn-hidden');",
  'Fix 1a'
);
tryReplace(
  "const tabsEl = document.getElementById('adminTabs'); tabsEl.style.display = 'flex';",
  "const tabsEl = document.getElementById('adminTabs'); tabsEl.classList.remove('admin-tabs-hidden');",
  'Fix 1b'
);

// Fix 9: Null-check adminProfile in renderAdminShell
tryReplace(
  "function renderAdminShell(){ const isManager",
  "function renderAdminShell(){ if(!adminProfile){ renderAdminLogin(); return; } const isManager",
  'Fix 9a'
);

// Fix 9b: openAdmin null check
tryReplace(
  "if(session){ adminSession = session; await loadAdminProfile(); renderAdminShell(); } else { renderAdminLogin(); }",
  "if(session){ adminSession = session; await loadAdminProfile(); if(adminProfile){ renderAdminShell(); } else { await sb.auth.signOut(); renderAdminLogin(); } } else { renderAdminLogin(); }",
  'Fix 9b'
);

// Fix 10: Clean up redundant code in adminLogout
tryReplace(
  "async function adminLogout(){ await sb.auth.signOut(); adminSession = null; adminProfile = null; unsubscribeChat(); closeAdmin(); document.body.classList.remove('admin-mode'); document.querySelector('.admin-sidebar')?.classList.remove('open'); document.querySelector('.admin-sidebar-overlay')?.classList.remove('open'); }",
  "async function adminLogout(){ await sb.auth.signOut(); adminSession = null; adminProfile = null; unsubscribeChat(); closeAdmin(); }",
  'Fix 10'
);

// Fix 3a: Add escapeHtml function after money function
tryReplace(
  "function money(n){ return (n||0).toLocaleString('fr-FR') + ' FCFA'; }",
  "function money(n){ return (n||0).toLocaleString('fr-FR') + ' FCFA'; }\n" + escapeHtmlFn,
  'Fix 3a'
);

// Fix 3b: Product form name - replace no-op .replace(/"/g,'"') with escapeHtml
c = c.replace(/product\.name\.replace\(\/\*"\*\/g,'"'\)/g, "escapeHtml(product.name)");
// We need to check if the pattern actually matched by checking if the old pattern still exists
if (!c.includes("product.name.replace")) {
  changes.push('Fix 3b: Product form name escaping: OK');
} else {
  changes.push('Fix 3b: Product form name escaping: NOT FOUND');
}

// Fix 3c: Product description escaping
tryReplace(
  "product ? (product.description||'') : ''",
  "product ? escapeHtml(product.description||'') : ''",
  'Fix 3c'
);

// Fix 3d: Point form name - replace no-op .replace(/"/g,'"') with escapeHtml
c = c.replace(/point\.name\.replace\(\/\*"\*\/g,'"'\)/g, "escapeHtml(point.name)");
if (!c.includes("point.name.replace")) {
  changes.push('Fix 3d: Point form name escaping: OK');
} else {
  changes.push('Fix 3d: Point form name escaping: NOT FOUND');
}

// Fix 3e: Point form address - replace no-op .replace(/"/g,'"') with escapeHtml
c = c.replace(/point\.address\.replace\(\/\*"\*\/g,'"'\)/g, "escapeHtml(point.address)");
if (!c.includes("point.address.replace")) {
  changes.push('Fix 3e: Point form address escaping: OK');
} else {
  changes.push('Fix 3e: Point form address escaping: NOT FOUND');
}

// Fix 3f: Point phone1, phone2, map_query escaping
tryReplace("point ? (point.phone1||'') : ''", "point ? escapeHtml(point.phone1||'') : ''", 'Fix 3f1');
tryReplace("point ? (point.phone2||'') : ''", "point ? escapeHtml(point.phone2||'') : ''", 'Fix 3f2');
tryReplace("point ? (point.map_query||'') : ''", "point ? escapeHtml(point.map_query||'') : ''", 'Fix 3f3');

// Fix 4: Sidebar toggle - add/remove sidebar-open class on admin-panel
tryReplace(
  "sidebar.classList.add('open'); overlay.classList.add('open'); } }",
  "sidebar.classList.add('open'); overlay.classList.add('open'); document.querySelector('.admin-panel')?.classList.add('sidebar-open'); } }",
  'Fix 4a'
);
tryReplace(
  "if(sidebar) sidebar.classList.remove('open'); if(overlay) overlay.classList.remove('open'); }",
  "if(sidebar) sidebar.classList.remove('open'); if(overlay) overlay.classList.remove('open'); document.querySelector('.admin-panel')?.classList.remove('sidebar-open'); }",
  'Fix 4b'
);

// Fix 5: switchAdminTab - remove caisse-active class
tryReplace(
  "adminActiveTab = tab; unsubscribeChat();",
  "adminActiveTab = tab; unsubscribeChat(); const caisseBody = document.querySelector('.admin-body'); if(caisseBody) caisseBody.classList.remove('caisse-active');",
  'Fix 5'
);

// Fix 6: importOrderToCaisse - use product_id instead of name
tryReplace(
  "const product = PRODUCTS.find(p=>p.name===item.product_name); if(product){ caisseCart.push({id:product.id, qty:item.qty}); }",
  "const product = item.product_id ? PRODUCTS.find(p=>p.id===item.product_id) : PRODUCTS.find(p=>p.name===item.product_name); if(product){ caisseCart.push({id:product.id, qty:item.qty}); }",
  'Fix 6'
);

// Fix 8: Reset file input after upload
tryReplace(
  "const file = event.target.files[0]; if(!file) return;",
  "const file = event.target.files[0]; if(!file) return; event.target.value = '';",
  'Fix 8'
);

// Fix 11: Null checks in cart/caisse rendering
tryReplace(
  "function cartTotal(){ return cart.reduce((sum,c)=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return sum + p.price * c.qty; },0); }",
  "function cartTotal(){ return cart.reduce((sum,c)=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return p ? sum + p.price * c.qty : sum; },0); }",
  'Fix 11d'
);
tryReplace(
  "container.innerHTML = caisseCart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return `<div style=",
  "container.innerHTML = caisseCart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); if(!p) return ''; return `<div style=",
  'Fix 11a'
);
tryReplace(
  "const total = caisseCart.reduce((sum,c)=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return sum + p.price * c.qty; },0);",
  "const total = caisseCart.reduce((sum,c)=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return p ? sum + p.price * c.qty : sum; },0);",
  'Fix 11b'
);
tryReplace(
  "const lines = caisseCart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return {id:p.id, name:p.name, qty:c.qty, price:p.price, sub:p.price*c.qty}; }); const total = lines.reduce((s,l)=>s+l.sub,0);",
  "const lines = caisseCart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return p ? {id:p.id, name:p.name, qty:c.qty, price:p.price, sub:p.price*c.qty} : null; }).filter(Boolean); const total = lines.reduce((s,l)=>s+l.sub,0);",
  'Fix 11c'
);
tryReplace(
  "const lines = cart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return {id:p.id, name:p.name, qty:c.qty, price:p.price, sub:p.price*c.qty}; });",
  "const lines = cart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return p ? {id:p.id, name:p.name, qty:c.qty, price:p.price, sub:p.price*c.qty} : null; }).filter(Boolean);",
  'Fix 11e'
);

// Fix 12: Escape HTML in rendered user content
// 12a: renderChatMessages
tryReplace(
  "return `<div class=\\"chat-bubble ${mine?'mine':'theirs'}\\">${m.body}<div class=\\"chat-meta\\">${m.sender_name || ''} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`; }).join('');",
  "return `<div class=\\"chat-bubble ${mine?'mine':'theirs'}\\">${escapeHtml(m.body)}<div class=\\"chat-meta\\">${escapeHtml(m.sender_name || '')} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`; }).join('');",
  'Fix 12a'
);

// 12b: subscribeToChat
tryReplace(
  "container.insertAdjacentHTML('beforeend', `<div class=\\"chat-bubble ${mine?'mine':'theirs'}\\">${m.body}<div class=\\"chat-meta\\">${m.sender_name || ''} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`);",
  "container.insertAdjacentHTML('beforeend', `<div class=\\"chat-bubble ${mine?'mine':'theirs'}\\">${escapeHtml(m.body)}<div class=\\"chat-meta\\">${escapeHtml(m.sender_name || '')} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`);",
  'Fix 12b'
);

// 12c: renderPendingOrders
tryReplace(
  "container.innerHTML = CACHED_PENDING_ORDERS.map(order=>`<div class=\\"pending-order-card\\" id=\\"pending-${order.id}\\"><div class=\\"order-info\\"><div class=\\"order-client\\">${order.client_name}</div><div class=\\"order-detail\\">${order.sale_items.map(i=>i.product_name).join(', ')}</div>",
  "container.innerHTML = CACHED_PENDING_ORDERS.map(order=>`<div class=\\"pending-order-card\\" id=\\"pending-${order.id}\\"><div class=\\"order-info\\"><div class=\\"order-client\\">${escapeHtml(order.client_name)}</div><div class=\\"order-detail\\">${order.sale_items.map(i=>escapeHtml(i.product_name)).join(', ')}</div>",
  'Fix 12c'
);

// 12d: importOrderToCaisse confirm dialog
tryReplace(
  "if(!confirm(`Importer la commande de ${order.client_name} (${money(order.total)}) ?`)) return;",
  "if(!confirm(`Importer la commande de ${escapeHtml(order.client_name)} (${money(order.total)}) ?`)) return;",
  'Fix 12d'
);

// Fix 7a: Add point selector for managers in assistance tab
tryReplace(
  "const body = document.getElementById('adminBody'); body.innerHTML = `<div class=\\"admin-toolbar\\"><div class=\\"admin-stat\\"><b>Assistance</b></div></div><div class=\\"chat-wrap\\">",
  "const body = document.getElementById('adminBody'); const chatPointSelectorHtml = isManager ? `<div class=\\"field\\" style=\\"margin-bottom:0;min-width:200px;\\"><label>Point de vente</label><select id=\\"chatPointSelect\\" onchange=\\"onChatPointChange(this.value)\\">${POINTS.map(p=>`<option value=\\"${p.id}\\" ${p.id===chatSelectedPoint?'selected':''}>${p.name}</option>`).join('')}</select></div>` : ''; body.innerHTML = `<div class=\\"admin-toolbar\\">${chatPointSelectorHtml}<div class=\\"admin-stat\\"><b>Assistance</b></div></div><div class=\\"chat-wrap\\">",
  'Fix 7a'
);

// Fix 7b: Add onChatPointChange function
tryReplace(
  "function onSalesFilterChange(val){ salesSelectedPoint = val; loadAndRenderSales(); }",
  "function onSalesFilterChange(val){ salesSelectedPoint = val; loadAndRenderSales(); }\nfunction onChatPointChange(id){ chatSelectedPoint = id; loadChatMessages(); subscribeToChat(); }",
  'Fix 7b'
);

// Write the file
fs.writeFileSync('c:/Tokcos/index.html', c, 'utf8');

console.log('=== Changes applied: ===');
changes.forEach(ch => console.log('  - ' + ch));
console.log('');
console.log('Remaining style.display for adminLogoutBtn/adminTabs:', (c.match(/adminLogoutBtn.*style\.display|adminTabs.*style\.display/g) || []).length);
console.log('escapeHtml function present:', c.includes('function escapeHtml'));
console.log('File size:', c.length);
