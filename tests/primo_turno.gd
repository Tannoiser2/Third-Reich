extends SceneTree
## I primi turni di Barbarossa: attacchi per fase
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1], int(args[0]))
	var ia := IA.new(m)
	var passi := 0
	var turni := 0
	var ultimo := -1
	var guerra := false
	m.evento.connect(func(t):
		if guerra and m.s["lato"] == "asse" and (t.begins_with("Attacco") or t.contains("avanzano")):
			print("  [", m.s["fase"], "] ", t.substr(0, 110)))
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		if guerra and r["k"] in ["sfruttamento"] and m.s["lato"] == "asse":
			pass
		var d := ia.decidi(r)
		if guerra and m.s["lato"] == "asse" and d.get("t", "") == "muovi" and m.s["fase"] == "sfruttamento":
			print("  [sfruttamento] muove ", d["u"], " ", m.s["u"][d["u"]]["t"], " da ", m.s["u"][d["u"]]["h"], " a ", d["h"])
		var fase: String = m.s["fase"]
		var lato: String = m.s["lato"]
		var res := m.applica(d)
		if guerra and lato == "asse" and d.get("t", "") == "attacca" and res.has("risultato"):
			print("  [", fase, "] ", res["risultato"].get("testo", "").substr(0, 100))
		if guerra and lato == "asse" and d.get("t", "") == "avanza":
			print("  [", fase, "] avanzano ", d.get("u", []).size())
		if not res["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if m.s["pot"]["GER"]["guerra"].has("URSS") and not guerra:
			guerra = true
			print("== guerra ", m.data_testo())
		if guerra and int(m.s["turno"]) != ultimo:
			ultimo = int(m.s["turno"])
			turni += 1
			print("== turno ", m.data_testo())
			if turni > 2: break
	quit()
