extends SceneTree
## Partita automatica IA contro IA: godot --headless --path . -s res://tests/sim.gd -- [seme] [modo]
func _initialize():
	var args := OS.get_cmdline_user_args()
	var seme := int(args[0]) if args.size() > 0 else 7
	var modo: String = args[1] if args.size() > 1 else "base"
	var m := Motore.new()
	m.nuova(modo, seme)
	var ia := IA.new(m)
	var tutto := []
	m.evento.connect(func(t): tutto.append(m.data_testo() + " | " + t))
	var passi := 0
	var t0 := Time.get_ticks_msec()
	var turno := -1
	var rifiuti := 0
	var dumped := false
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		var d := ia.decidi(r)
		var res := m.applica(d)
		if not res["ok"]:
			rifiuti += 1
			if rifiuti > 50:
				print("BLOCCO: ", r, " ", d, " ", res)
				var f := m.applica({"t": "fine"})
				rifiuti = 0
		passi += 1
		if not dumped and OS.get_environment("DUMP") != "" and m.data_testo() == OS.get_environment("DUMP") and r["k"] == "combattimento" and m.s["lato"] == OS.get_environment("DUMPL"):
			dumped = true
			var f := FileAccess.open("/tmp/dump.json", FileAccess.WRITE)
			f.store_string(JSON.stringify(m.s))
			f.close()
		if int(m.s["turno"]) != turno:
			turno = int(m.s["turno"])
			var cont := {}
			for uid in m.s["u"]:
				var n: String = m.s["u"][uid]["n"]
				cont[n] = int(cont.get(n, 0)) + 1
			var brp := {}
			for p in Dati.MAGGIORI:
				brp[p] = m.s["pot"][p]["brp"]
			print("%s ob.Asse=%d unità=%s BRP=%s (%d ms)" % [m.data_testo(), m.obiettivi_asse(), cont, brp, Time.get_ticks_msec() - t0])
	print("FINE: ", m.s["fine"], " passi=", passi, " ms=", Time.get_ticks_msec() - t0)
	var nl := int(OS.get_environment("NLOG")) if OS.get_environment("NLOG") != "" else 15
	for l in tutto.slice(maxi(0, tutto.size() - nl)):
		print("  ", l)
	quit()
