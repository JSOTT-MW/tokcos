# -*- coding: utf-8 -*-
"""Insert the new menu items into the Supabase products table."""
import json
import urllib.request
import urllib.error

SUPABASE_URL = 'https://tsqzvqadawlgkmeiitis.supabase.co'
SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRzcXp2cWFkYXdsZ2ttZWlpdGlzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUyMzE2OTAsImV4cCI6MjEwMDgwNzY5MH0.Yz8EQTt1lY1kmn0KPpa7ozUEwf3RNLRaq2toJqnDgT4'

# Menu items as provided by the user
PRODUCTS = [
    # --- Café & Douceurs Chaudes ---
    {"cat": "cafe", "name": "Café Touba Wakan Khakhan", "price": 500,
     "description": "Café Touba signature, à la saveur intense et épicée.", "icon": "☕", "active": True},
    {"cat": "cafe", "name": "Café en poudre", "price": 500,
     "description": "Café moulu en poudre, prêt à l'infusion.", "icon": "☕", "active": True},
    {"cat": "cafe", "name": "Café en grains pour Machine à café", "price": 1000,
     "description": "Grains de café torréfiés pour machine à café.", "icon": "☕", "active": True},
    {"cat": "cafe", "name": "Coffee chocolat / Lait à la menthe", "price": 700,
     "description": "Coffee chocolat chaud ou lait à la menthe.", "icon": "☕", "active": True},
    {"cat": "cafe", "name": "Café Lait", "price": 600,
     "description": "Café au lait, servi chaud.", "icon": "☕", "active": True},

    # --- Wass, Jus & Saveurs Locales ---
    {"cat": "wass", "name": "Soft Wass", "price": 500,
     "description": "Wass rafraîchissant à base de jasmin.", "icon": "🥤", "active": True},
    {"cat": "wass", "name": "Wonder Wass", "price": 600,
     "description": "Wass à base de bouye (fruit du baobab).", "icon": "🥤", "active": True},
    {"cat": "wass", "name": "Tarkinda", "price": 500,
     "description": "Boisson au gingembre (Tarkinda).", "icon": "🥤", "active": True},
    {"cat": "wass", "name": "Bisap (Bissap)", "price": 500,
     "description": "Bissap, jus d'hibiscus rafraîchissant.", "icon": "🥤", "active": True},
    {"cat": "wass", "name": "Jus locaux, Smoothie, Jus de fruits", "price": 800,
     "description": "Jus locaux, smoothies et jus de fruits (orange, pomme...), sirop.", "icon": "🥤", "active": True},
]

def api_request(method, path, payload=None):
    url = SUPABASE_URL + path
    data = json.dumps(payload).encode('utf-8') if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header('apikey', SUPABASE_ANON_KEY)
    req.add_header('Authorization', 'Bearer ' + SUPABASE_ANON_KEY)
    req.add_header('Content-Type', 'application/json')
    req.add_header('Prefer', 'return=representation')
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode('utf-8'))
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode('utf-8')

def main():
    # First, fetch existing products to avoid duplicates
    status, existing = api_request('GET', '/rest/v1/products?select=name')
    if status != 200:
        print(f"Erreur lecture produits ({status}): {existing}")
        return
    existing_names = {p['name'] for p in existing}

    inserted = 0
    skipped = 0
    for prod in PRODUCTS:
        if prod['name'] in existing_names:
            print(f"SKIP (déjà présent): {prod['name']}")
            skipped += 1
            continue
        status, resp = api_request('POST', '/rest/v1/products', prod)
        if status in (200, 201):
            print(f"OK: {prod['name']}")
            inserted += 1
        else:
            print(f"ERREUR ({status}) pour {prod['name']}: {resp}")

    print(f"\nTerminé. {inserted} insérés, {skipped} ignorés (déjà présents).")

if __name__ == '__main__':
    main()