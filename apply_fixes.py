#!/usr/bin/env python3
"""Apply all bug fixes to index.html"""
import re

with open('c:/Tokcos/index.html', 'r', encoding='utf-8') as f:
    c = f.read()

# Read the escapeHtml function from file
with open('c:/Tokcos/escape_fn.txt', 'r', encoding='utf-8') as f:
    escape_html_fn = f.read().strip()

changes = []

def replace_once(old, new, label):
    global c
    if old in c:
        c = c.replace(old, new, 1)
        changes.append(f"{label}: OK")
    else:
        changes.append(f"{label}: NOT FOUND")

# ============================================================
# Fix 1 (completion): renderAdminShell - use classList instead of style.display
# ============================================================
replace_once(
    "document.getElementById('adminLogoutBtn').style.display = 'inline-flex';",
    "document.getElementById('adminLogoutBtn').classList.remove('admin-logout-btn-hidden');",
    'Fix 1a: renderAdminShell logout classList'
)
replace_once(
    "const tabsEl = document.getElementById('adminTabs'); tabsEl.style.display = 'flex';",
    "const tabsEl = document.getElementById('adminTabs'); tabsEl.classList.remove('admin-tabs-hidden');",
    'Fix 1b: renderAdminShell tabs classList'
)

# ============================================================
# Fix 9: Null-check adminProfile in renderAdminShell
# ============================================================
replace_once(
    "function renderAdminShell(){ const isManager",
    "function renderAdminShell(){ if(!adminProfile){ renderAdminLogin(); return; } const isManager",
    'Fix 9a: renderAdminShell null check'
)

# Fix 9b: openAdmin null check
replace_once(
    "if(session){ adminSession = session; await loadAdminProfile(); renderAdminShell(); } else { renderAdminLogin(); }",
    "if(session){ adminSession = session; await loadAdminProfile(); if(adminProfile){ renderAdminShell(); } else { await sb.auth.signOut(); renderAdminLogin(); } } else { renderAdminLogin(); }",
    'Fix 9b: openAdmin null check'
)

# ============================================================
# Fix 10: Clean up redundant code in adminLogout
# ============================================================
replace_once(
    "async function adminLogout(){ await sb.auth.signOut(); adminSession = null; adminProfile = null; unsubscribeChat(); closeAdmin(); document.body.classList.remove('admin-mode'); document.querySelector('.admin-sidebar')?.classList.remove('open'); document.querySelector('.admin-sidebar-overlay')?.classList.remove('open'); }",
    "async function adminLogout(){ await sb.auth.signOut(); adminSession = null; adminProfile = null; unsubscribeChat(); closeAdmin(); }",
    'Fix 10: Clean adminLogout'
)

# ============================================================
# Fix 3a: Add escapeHtml function after money function
# ============================================================
replace_once(
    "function money(n){ return (n||0).toLocaleString('fr-FR') + ' FCFA'; }",
    "function money(n){ return (n||0).toLocaleString('fr-FR') + ' FCFA'; }\n" + escape_html_fn,
    'Fix 3a: Added escapeHtml function'
)

# ============================================================
# Fix 3b: Product form name - replace no-op .replace(/"/g,'"') with escapeHtml
# The actual text in file: product.name.replace(/"/g,'"')
# ============================================================
c = re.sub(r'product\.name\.replace\(/"/g,\x27"\x27\)', 'escapeHtml(product.name)', c)
if not re.search(r'product\.name\.replace', c):
    changes.append('Fix 3b: Product form name escaping: OK')
else:
    changes.append('Fix 3b: Product form name escaping: NOT FOUND')

# Fix 3c: Product description escaping
replace_once(
    "product ? (product.description||'') : ''",
    "product ? escapeHtml(product.description||'') : ''",
    'Fix 3c: Product form desc escaping'
)

# Fix 3d: Point form name
c = re.sub(r'point\.name\.replace\(/"/g,\x27"\x27\)', 'escapeHtml(point.name)', c)
if not re.search(r'point\.name\.replace', c):
    changes.append('Fix 3d: Point form name escaping: OK')
else:
    changes.append('Fix 3d: Point form name escaping: NOT FOUND')

# Fix 3e: Point form address
c = re.sub(r'point\.address\.replace\(/"/g,\x27"\x27\)', 'escapeHtml(point.address)', c)
if not re.search(r'point\.address\.replace', c):
    changes.append('Fix 3e: Point form address escaping: OK')
else:
    changes.append('Fix 3e: Point form address escaping: NOT FOUND')

# Fix 3f: Point phone1, phone2, map_query
replace_once("point ? (point.phone1||'') : ''", "point ? escapeHtml(point.phone1||'') : ''", 'Fix 3f1')
replace_once("point ? (point.phone2||'') : ''", "point ? escapeHtml(point.phone2||'') : ''", 'Fix 3f2')
replace_once("point ? (point.map_query||'') : ''", "point ? escapeHtml(point.map_query||'') : ''", 'Fix 3f3')

# ============================================================
# Fix 4: Sidebar toggle - add/remove sidebar-open class on admin-panel
# ============================================================
replace_once(
    "sidebar.classList.add('open'); overlay.classList.add('open'); } }",
    "sidebar.classList.add('open'); overlay.classList.add('open'); document.querySelector('.admin-panel')?.classList.add('sidebar-open'); } }",
    'Fix 4a: toggleSidebar adds sidebar-open'
)
replace_once(
    "if(sidebar) sidebar.classList.remove('open'); if(overlay) overlay.classList.remove('open'); }",
    "if(sidebar) sidebar.classList.remove('open'); if(overlay) overlay.classList.remove('open'); document.querySelector('.admin-panel')?.classList.remove('sidebar-open'); }",
    'Fix 4b: closeSidebar removes sidebar-open'
)

# ============================================================
# Fix 5: switchAdminTab - remove caisse-active class
# ============================================================
replace_once(
    "adminActiveTab = tab; unsubscribeChat();",
    "adminActiveTab = tab; unsubscribeChat(); document.querySelector('.admin-body')?.classList.remove('caisse-active');",
    'Fix 5: switchAdminTab removes caisse-active'
)

# ============================================================
# Fix 6: importOrderToCaisse - use product_id instead of name
# ============================================================
replace_once(
    "const product = PRODUCTS.find(p=>p.name===item.product_name); if(product){ caisseCart.push({id:product.id, qty:item.qty}); }",
    "const product = item.product_id ? PRODUCTS.find(p=>p.id===item.product_id) : PRODUCTS.find(p=>p.name===item.product_name); if(product){ caisseCart.push({id:product.id, qty:item.qty}); }",
    'Fix 6: importOrderToCaisse uses product_id'
)

# ============================================================
# Fix 8: Reset file input after upload
# ============================================================
replace_once(
    "const file = event.target.files[0]; if(!file) return;",
    "const file = event.target.files[0]; if(!file) return; event.target.value = '';",
    'Fix 8: Reset file input'
)

# ============================================================
# Fix 11: Null checks in cart/caisse rendering
# ============================================================
replace_once(
    "function cartTotal(){ return cart.reduce((sum,c)=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return sum + p.price * c.qty; },0); }",
    "function cartTotal(){ return cart.reduce((sum,c)=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return p ? sum + p.price * c.qty : sum; },0); }",
    'Fix 11d: cartTotal null check'
)
replace_once(
    "container.innerHTML = caisseCart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return `<div style=",
    "container.innerHTML = caisseCart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); if(!p) return ''; return `<div style=",
    'Fix 11a: renderCaisseCart null check'
)
replace_once(
    "const total = caisseCart.reduce((sum,c)=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return sum + p.price * c.qty; },0);",
    "const total = caisseCart.reduce((sum,c)=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return p ? sum + p.price * c.qty : sum; },0);",
    'Fix 11b: caisseCart total null check'
)
replace_once(
    "const lines = caisseCart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return {id:p.id, name:p.name, qty:c.qty, price:p.price, sub:p.price*c.qty}; }); const total = lines.reduce((s,l)=>s+l.sub,0);",
    "const lines = caisseCart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return p ? {id:p.id, name:p.name, qty:c.qty, price:p.price, sub:p.price*c.qty} : null; }).filter(Boolean); const total = lines.reduce((s,l)=>s+l.sub,0);",
    'Fix 11c: validerVenteCaisse null check'
)
replace_once(
    "const lines = cart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return {id:p.id, name:p.name, qty:c.qty, price:p.price, sub:p.price*c.qty}; });",
    "const lines = cart.map(c=>{ const p = PRODUCTS.find(pp=>pp.id===c.id); return p ? {id:p.id, name:p.name, qty:c.qty, price:p.price, sub:p.price*c.qty} : null; }).filter(Boolean);",
    'Fix 11e: submitOrder null check'
)

# ============================================================
# Fix 12: Escape HTML in rendered user content
# ============================================================

# 12a: renderChatMessages - escape m.body and m.sender_name
old_12a = r"return `<div class=\"chat-bubble ${mine?'mine':'theirs'}\">${m.body}<div class=\"chat-meta\">${m.sender_name || ''} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`; }).join('');"
new_12a = r"return `<div class=\"chat-bubble ${mine?'mine':'theirs'}\">${escapeHtml(m.body)}<div class=\"chat-meta\">${escapeHtml(m.sender_name || '')} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`; }).join('');"
replace_once(old_12a, new_12a, 'Fix 12a: renderChatMessages escaping')

# 12b: subscribeToChat
old_12b = r"container.insertAdjacentHTML('beforeend', `<div class=\"chat-bubble ${mine?'mine':'theirs'}\">${m.body}<div class=\"chat-meta\">${m.sender_name || ''} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`);"
new_12b = r"container.insertAdjacentHTML('beforeend', `<div class=\"chat-bubble ${mine?'mine':'theirs'}\">${escapeHtml(m.body)}<div class=\"chat-meta\">${escapeHtml(m.sender_name || '')} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`);"
replace_once(old_12b, new_12b, 'Fix 12b: subscribeToChat escaping')

# 12c: renderPendingOrders
old_12c = r"container.innerHTML = CACHED_PENDING_ORDERS.map(order=>`<div class=\"pending-order-card\" id=\"pending-${order.id}\"><div class=\"order-info\"><div class=\"order-client\">${order.client_name}</div><div class=\"order-detail\">${order.sale_items.map(i=>i.product_name).join(', ')}</div>"
new_12c = r"container.innerHTML = CACHED_PENDING_ORDERS.map(order=>`<div class=\"pending-order-card\" id=\"pending-${order.id}\"><div class=\"order-info\"><div class=\"order-client\">${escapeHtml(order.client_name)}</div><div class=\"order-detail\">${order.sale_items.map(i=>escapeHtml(i.product_name)).join(', ')}</div>"
replace_once(old_12c, new_12c, 'Fix 12c: renderPendingOrders escaping')

# 12d: importOrderToCaisse confirm dialog
replace_once(
    "if(!confirm(`Importer la commande de ${order.client_name} (${money(order.total)}) ?`)) return;",
    "if(!confirm(`Importer la commande de ${escapeHtml(order.client_name)} (${money(order.total)}) ?`)) return;",
    'Fix 12d: importOrderToCaisse confirm escaping'
)

# ============================================================
# Fix 7a: Add point selector for managers in assistance tab
# ============================================================
old_7a = r"const body = document.getElementById('adminBody'); body.innerHTML = `<div class=\"admin-toolbar\"><div class=\"admin-stat\"><b>Assistance</b></div></div><div class=\"chat-wrap\">"
new_7a = r"const body = document.getElementById('adminBody'); const chatPointSelectorHtml = isManager ? `<div class=\"field\" style=\"margin-bottom:0;min-width:200px;\"><label>Point de vente</label><select id=\"chatPointSelect\" onchange=\"onChatPointChange(this.value)\">${POINTS.map(p=>`<option value=\"${p.id}\" ${p.id===chatSelectedPoint?'selected':''}>${p.name}</option>`).join('')}</select></div>` : ''; body.innerHTML = `<div class=\"admin-toolbar\">${chatPointSelectorHtml}<div class=\"admin-stat\"><b>Assistance</b></div></div><div class=\"chat-wrap\">"
replace_once(old_7a, new_7a, 'Fix 7a: Added chat point selector for managers')

# Fix 7b: Add onChatPointChange function
replace_once(
    "function onSalesFilterChange(val){ salesSelectedPoint = val; loadAndRenderSales(); }",
    "function onSalesFilterChange(val){ salesSelectedPoint = val; loadAndRenderSales(); }\nfunction onChatPointChange(id){ chatSelectedPoint = id; loadChatMessages(); subscribeToChat(); }",
    'Fix 7b: Added onChatPointChange function'
)

# ============================================================
# Write the file
# ============================================================
with open('c:/Tokcos/index.html', 'w', encoding='utf-8') as f:
    f.write(c)

print('=== Changes applied: ===')
for ch in changes:
    print(f'  - {ch}')
print('')
print('Remaining style.display for adminLogoutBtn/adminTabs:', len(re.findall(r'adminLogoutBtn.*style\.display|adminTabs.*style\.display', c)))
print('escapeHtml function present:', 'function escapeHtml' in c)
print('File size:', len(c))
