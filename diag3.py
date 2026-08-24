# -*- coding: utf-8 -*-
c = open('c:/Tokcos/index.html', 'r', encoding='utf-8').read()
lines = c.split('\n')
out = []

def find(pattern, label, before=0, after=600):
    idx = c.find(pattern)
    if idx == -1:
        out.append('=== %s: NOT FOUND ===' % label)
        return
    line_no = c[:idx].count('\n') + 1
    start_idx = c.rfind('\n', 0, idx)
    seg = c[idx:idx + after]
    out.append('=== %s (line ~%d) ===' % (label, line_no))
    out.append(repr(seg))
    out.append('')

find('function renderAdminShell', 'renderAdminShell', after=800)
find('function money', 'money function', after=400)
find("document.getElementById('adminLogoutBtn')", 'adminLogoutBtn usage', after=400)
find("const tabsEl = document.getElementById('adminTabs')", 'adminTabs usage', after=400)
find('function cartTotal', 'cartTotal', after=500)
find('caisseCart.map', 'caisseCart.map', after=500)
find("renderChatMessages", 'renderChatMessages', after=500)
find('insertAdjacentHTML', 'insertAdjacentHTML', after=500)
find('CACHED_PENDING_ORDERS.map', 'CACHED_PENDING_ORDERS.map', after=500)
find('product.description', 'product.description', after=400)
find('point.phone1', 'point.phone1', after=400)
find('async function openAdmin', 'openAdmin', after=600)
find('async function adminLogout', 'adminLogout', after=500)
find('function switchAdminTab', 'switchAdminTab', after=500)
find('importOrderToCaisse', 'importOrderToCaisse', after=800)
find("const file = event.target.files[0]", 'file input', after=300)
find('sidebar.classList.add', 'sidebar toggle', after=400)
find("const lines = cart.map", 'cart lines', after=400)
find("const lines = caisseCart.map", 'caisseCart lines', after=400)
find('product.name.replace', 'product.name.replace', after=300)
find('point.name.replace', 'point.name.replace', after=300)
find('point.address.replace', 'point.address.replace', after=300)

with open('c:/Tokcos/diag3.txt', 'w', encoding='utf-8') as f:
    f.write('\n'.join(out))
print('written diag3.txt')