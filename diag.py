import re

f = open('c:/Tokcos/index.html', 'r', encoding='utf-8')
c = f.read()
f.close()

out = []

# Check Fix 9a
idx = c.find('renderAdminShell(){')
if idx == -1:
    idx = c.find('renderAdminShell()')
out.append('=== renderAdminShell ===')
out.append(repr(c[idx:idx+120]))

# Check Fix 12a - chat messages (m.body)
idx = c.find('m.body}<div')
if idx == -1:
    idx = c.find('m.body')
out.append('\n=== m.body context ===')
out.append(repr(c[idx-60:idx+100]))

# Check Fix 12b
idx = c.find('insertAdjacentHTML')
out.append('\n=== insertAdjacentHTML ===')
out.append(repr(c[idx:idx+200]))

# Check Fix 12c
idx = c.find('order-client')
out.append('\n=== order-client ===')
out.append(repr(c[idx:idx+200]))

# Check Fix 7a
idx = c.find('<b>Assistance</b>')
out.append('\n=== Assistance ===')
out.append(repr(c[idx-120:idx+200]))

# Check the chat wrap section
idx = c.find('chat-wrap')
out.append('\n=== chat-wrap ===')
out.append(repr(c[idx-50:idx+300]))

with open('c:/Tokcos/diag.txt', 'w') as f:
    f.write('\n'.join(out))

print('Done - see diag.txt')
