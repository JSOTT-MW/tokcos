import re

f = open('c:/Tokcos/index.html', 'r', encoding='utf-8')
c = f.read()
f.close()

changes = []

def replace_once(old, new, label):
    global c
    if old in c:
        c = c.replace(old, new, 1)
        changes.append(label + ': OK')
    else:
        changes.append(label + ': NOT FOUND')

# Read escapeHtml function
with open('c:/Tokcos/escape_fn.txt', 'r', encoding='utf-8') as f:
    escape_html_fn = f.read().strip()

# ============================================================
# Fix 9a: renderAdminShell - null check
# ============================================================
replace_once(
    "function renderAdminShell(){\n  const isManager = adminProfile.role==='manager';",
    "function renderAdminShell(){\n  if(!adminProfile){ renderAdminLogin(); return; }\n  const isManager = adminProfile.role==='manager';",
    'Fix 9a: renderAdminShell null check'
)

# ============================================================
# Fix 12a: renderChatMessages - escape m.body and m.sender_name
# ============================================================
old_12a = """return `<div class="chat-bubble ${mine?'mine':'theirs'}">${m.body}<div class="chat-meta">${m.sender_name || ''} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`; }).join('');"""
new_12a = """return `<div class="chat-bubble ${mine?'mine':'theirs'}">${escapeHtml(m.body)}<div class="chat-meta">${escapeHtml(m.sender_name || '')} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`; }).join('');"""
replace_once(old_12a, new_12a, 'Fix 12a: renderChatMessages escaping')

# ============================================================
# Fix 12b: subscribeToChat - escape m.body and m.sender_name
# ============================================================
old_12b = """container.insertAdjacentHTML('beforeend', `<div class="chat-bubble ${mine?'mine':'theirs'}">${m.body}<div class="chat-meta">${m.sender_name || ''} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`);"""
new_12b = """container.insertAdjacentHTML('beforeend', `<div class="chat-bubble ${mine?'mine':'theirs'}">${escapeHtml(m.body)}<div class="chat-meta">${escapeHtml(m.sender_name || '')} · ${new Date(m.created_at).toLocaleString('fr-FR')}</div></div>`);"""
replace_once(old_12b, new_12b, 'Fix 12b: subscribeToChat escaping')

# ============================================================
# Fix 12c: renderPendingOrders - escape client_name and product_name
# ============================================================
old_12c = """container.innerHTML = CACHED_PENDING_ORDERS.map(order=>`<div class="pending-order-card" id="pending-${order.id}"><div class="order-info"><div class="order-client">${order.client_name}</div><div class="order-detail">${order.sale_items.map(i=>i.product_name).join(', ')}</div>"""
new_12c = """container.innerHTML = CACHED_PENDING_ORDERS.map(order=>`<div class="pending-order-card" id="pending-${order.id}"><div class="order-info"><div class="order-client">${escapeHtml(order.client_name)}</div><div class="order-detail">${order.sale_items.map(i=>escapeHtml(i.product_name)).join(', ')}</div>"""
replace_once(old_12c, new_12c, 'Fix 12c: renderPendingOrders escaping')

# ============================================================
# Fix 7a: Add point selector for managers in assistance tab
# ============================================================
old_7a = """const body = document.getElementById('adminBody'); body.innerHTML = `<div class="admin-toolbar"><div class="admin-stat"><b>Assistance</b></div></div><div class="chat-wrap">"""
new_7a = """const body = document.getElementById('adminBody'); const chatPointSelectorHtml = isManager ? `<div class="field" style="margin-bottom:0;min-width:200px;"><label>Point de vente</label><select id="chatPointSelect" onchange="onChatPointChange(this.value)">${POINTS.map(p=>`<option value="${p.id}" ${p.id===chatSelectedPoint?'selected':''}>${p.name}</option>`).join('')}</select></div>` : ''; body.innerHTML = `<div class="admin-toolbar">${chatPointSelectorHtml}<div class="admin-stat"><b>Assistance</b></div></div><div class="chat-wrap">"""
replace_once(old_7a, new_7a, 'Fix 7a: Added chat point selector for managers')

# Write the file
f = open('c:/Tokcos/index.html', 'w', encoding='utf-8')
f.write(c)
f.close()

print('=== Remaining changes applied: ===')
for ch in changes:
    print(f'  - {ch}')
print('')
print('File size:', len(c))
