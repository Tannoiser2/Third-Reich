extends SceneTree
## Avanzata in Russia: controllo delle città sovietiche e forze, stagione per stagione
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1], int(args[0]))
	var ia := IA.new(m)
	var turno := -1
	var passi := 0
	var citta := ["Riga", "Minsk", "Lvov", "Kiev", "Smolensk", "Leningrad", "Moscow", "Kharkov", "Rostov", "Stalingrad", "Sevastopol", "Odessa"]
	var ids := {}
	for id in m.D.esagoni:
		if m.D.esagoni[id]["citta"] in citta:
			ids[m.D.esagoni[id]["citta"]] = id
	var att := {}
	m.evento.connect(func(t):
		if t.contains("avanzano in"):
			att[m.data_testo()] = int(att.get(m.data_testo(), 0)) + 1)
	var limite := int(args[2]) if args.size() > 2 else 1944
	while not m.finita() and passi < 200000 and int(m.s["anno"]) <= limite:
		var r := m.richiesta()
		if not m.applica(ia.decidi(r))["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if int(m.s["turno"]) != turno:
			turno = int(m.s["turno"])
			if not m.s["pot"]["GER"]["guerra"].has("URSS"):
				continue
			var riga := ""
			for c in citta:
				if ids.has(c):
					riga += ("X" if m.lato(m.controllo(ids[c])) == "asse" else ".")
			var ge := 0
			var so := 0
			var colmax := 0
			for uid in m.s["u"]:
				var u: Dictionary = m.s["u"][uid]
				if not Motore._terrestre(u["t"]) or u["h"] == "USA": continue
				if u["n"] == "URSS": so += m.forza(uid)
				elif m.lato(u["n"]) == "asse" and m.D.esagoni[u["h"]]["c"] >= 33:
					ge += m.forza(uid)
					colmax = maxi(colmax, int(m.D.esagoni[u["h"]]["c"]))
			print(m.data_testo(), " ", riga, " asse a est=", ge, " sovietici=", so, " colonna max=", colmax, " avanzate=", att.get(m.data_testo(), 0))
	print("citta: ", citta)
	quit()
