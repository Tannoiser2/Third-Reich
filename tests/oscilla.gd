extends SceneTree
## Conta le pedine che tornano nell'esagono di due turni prima (avanti-indietro): -- seme modo
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1] if args.size() > 1 else "base", int(args[0]) if args.size() > 0 else 3)
	var ia := IA.new(m)
	var storia := {}  # uid -> lista posizioni a fine turno
	var turno := -1
	var passi := 0
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		var res := m.applica(ia.decidi(r))
		if not res["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if int(m.s["turno"]) != turno:
			turno = int(m.s["turno"])
			for uid in m.s["u"]:
				if not storia.has(uid): storia[uid] = []
				storia[uid].append(m.s["u"][uid]["h"])
			if turno > 16: break
	var aba := 0
	var mosse := 0
	var esempi := {}
	for uid in storia:
		var l: Array = storia[uid]
		for i in range(2, l.size()):
			if l[i] != l[i-1]: mosse += 1
			if l[i] == l[i-2] and l[i] != l[i-1]:
				aba += 1
				var n: String = m.s["u"][uid]["n"] if m.s["u"].has(uid) else "?"
				esempi[n] = int(esempi.get(n, 0)) + 1
	print("spostamenti=", mosse, " avanti-indietro=", aba, " per nazione=", esempi)
	quit()
