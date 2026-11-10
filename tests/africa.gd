extends SceneTree
## Attività nel Nord Africa e nel Mediterraneo: -- seme modo
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1] if args.size() > 1 else "base", int(args[0]) if args.size() > 0 else 3)
	var ia := IA.new(m)
	var D: Dati = m.D
	var AF := ["LIB", "EGI", "EGY", "TUN", "ALG", "MAR", "VIC"]
	var turno := -1
	var passi := 0
	var att := {}
	m.evento.connect(func(t):
		if t.begins_with("Attacco su"):
			var id: String = t.get_slice("(", 1).get_slice(")", 0)
			if D.esagoni.has(id) and D.esagoni[id]["n"] in AF:
				att[m.data_testo()] = int(att.get(m.data_testo(), 0)) + 1)
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		if not m.applica(ia.decidi(r))["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if int(m.s["turno"]) != turno:
			turno = int(m.s["turno"])
			var c := {}
			for uid in m.s["u"]:
				var u: Dictionary = m.s["u"][uid]
				var h: String = u["h"]
				if h != "USA" and D.esagoni.has(h) and D.esagoni[h]["n"] in AF and Motore._terrestre(u["t"]):
					var k: String = m.comandante(u["n"])
					c[k] = int(c.get(k, 0)) + m.forza(uid)
			var ctl := {}
			for h in D.esagoni:
				if D.esagoni[h]["n"] in ["LIB", "EGI", "EGY"]:
					var x := m.controllo(h)
					ctl[x] = int(ctl.get(x, 0)) + 1
			print(m.data_testo(), " forze in Africa=", c, " controllo Libia/Egitto=", ctl)
	print("attacchi in Africa per stagione: ", att)
	quit()
