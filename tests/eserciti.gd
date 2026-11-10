extends SceneTree
## Composizione degli eserciti tedesco e sovietico all'inizio di Barbarossa
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1], int(args[0]))
	var ia := IA.new(m)
	var passi := 0
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		if not m.applica(ia.decidi(r))["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if m.s["pot"]["GER"]["guerra"].has("URSS") and m.s["fase"] == "movimento":
			break
	for p in ["GER", "URSS"]:
		var c := {}
		for uid in m.s["u"]:
			var u: Dictionary = m.s["u"][uid]
			if u["n"] != p: continue
			var k := "%s %d-%d" % [u["t"], u["a"], u["m"]]
			c[k] = int(c.get(k, 0)) + 1
		print(m.data_testo(), " ", p, " brp=", m.s["pot"][p]["brp"], " ", c, " pool=", m.s["pool"][p].size())
	quit()
