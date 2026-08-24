# -*- coding: utf-8 -*-
c = open('c:/Tokcos/index.html', 'r', encoding='utf-8').read()
lines = []
checks = [
    ('Fix 1a: logoutBtn style.display', "document.getElementById('adminLogoutBtn').style.display = 'inline-flex';" in c),
    ('Fix 1b: adminTabs style.display', "const tabsEl = document.getElementById('adminTabs'); tabsEl.style.display = 'flex';" in c),
    ('Fix 9a: renderAdminShell null check', 'if(!adminProfile){ renderAdminLogin(); return; }' in c),
    ('Fix 9b: openAdmin null check', 'if(adminProfile){ renderAdminShell(); } else { await sb.auth.signOut(); renderAdminLogin(); }' in c),
    ('Fix 3a: escapeHtml function', 'function escapeHtml' in c),
    ('Fix 3c: product description escape', 'escapeHtml(product.description' in c),
    ('Fix 12a: chat messages escape', 'escapeHtml(m.body)' in c),
    ('Fix 12c: pending orders escape', 'escapeHtml(order.client_name)' in c),
    ('Fix 7a: chat point selector', 'chatPointSelect' in c),
    ('Fix 7b: onChatPointChange', 'onChatPointChange' in c),
    ('Fix 11a: caisseCart null check', 'if(!p) return' in c),
    ('money function', 'function money' in c),
    ('POINTS variable', 'POINTS' in c),
    ('m.body raw (unescaped)', '${m.body}' in c),
    ('m.sender_name raw (unescaped)', '${m.sender_name' in c),
]
for k, v in checks:
    lines.append(('OK  ' if v else 'MISS') + ' | ' + k)
with open('c:/Tokcos/diag2.txt', 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print('written', len(c))