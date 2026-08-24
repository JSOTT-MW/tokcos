# -*- coding: utf-8 -*-
c = open('c:/Tokcos/index.html', 'r', encoding='utf-8').read()
out = []

def find_all(pattern, label, ctx=350):
    out.append('=== %s ===' % label)
    start = 0
    count = 0
    while True:
        idx = c.find(pattern, start)
        if idx == -1:
            break
        count += 1
        out.append('--- occurrence %d ---' % count)
        out.append(repr(c[max(0, idx-80):idx+ctx]))
        start = idx + len(pattern)
    if count == 0:
        out.append('(none)')
    out.append('')

find_all('markOrderFulfilled', 'markOrderFulfilled', 700)
find_all('sidebar', 'sidebar', 300)
find_all('files[0]', 'files[0]', 300)
find_all('reduce(', 'reduce(', 300)
find_all('caisseCart', 'caisseCart', 500)
find_all('loadChatMessages', 'loadChatMessages', 500)
find_all("onChatPointChange", 'onChatPointChange', 400)
find_all('renderAdminCaisse', 'renderAdminCaisse', 1200)
find_all('renderAdminStock', 'renderAdminStock', 900)
find_all('product.description', 'product.description', 200)
find_all('product.name', 'product.name', 200)
find_all('point.name', 'point.name', 200)
find_all('point.phone', 'point.phone', 200)
find_all('importOrder', 'importOrder', 600)
find_all('CACHED_PENDING', 'CACHED_PENDING', 300)

with open('c:/Tokcos/diag4.txt', 'w', encoding='utf-8') as f:
    f.write('\n'.join(out))
print('written diag4.txt')