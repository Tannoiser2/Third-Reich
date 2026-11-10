extends SceneTree
## Preparazione di Barbarossa: forze dell'Asse vicine al confine sovietico a ogni stagione del 1941
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1], int(args[0]))
	var ia := IA.new(m)
	var passi := 0
	var fatto := {}
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		var dt := m.data_testo()
		if r.get("k", "") == "dichiarazioni" and m.s["lato"] == "asse" and dt.ends_with("1941") and not fatto.has(dt):
			fatto[dt] = true
			var d_est := ia._distanza_da(["URSS"])
			var asse := 0
			var tot := 0
			var ovest := 0
			for uid in m.s["u"]:
				var u: Dictionary = m.s["u"][uid]
				if not Motore._terrestre(u["t"]) or u["h"] == "USA" or u["n"] != "GER": continue
				tot += m.forza(uid)
				var portata := 5 if u["t"] == "cor" else 4
				if int(d_est.get(u["h"], 99)) <= portata: asse += m.forza(uid)
				elif m.D.esagoni[u["h"]]["n"] in ["FRA", "BEL", "NED", "LUX"]: ovest += m.forza(uid)
			print(dt, " Francia arresa=", m.s["pot"]["FRA"]["arresa"], " brp=", m.s["pot"]["GER"]["brp"], " tedeschi totali=", tot, " vicino all'URSS=", asse, " in Francia/Benelux=", ovest, " SR=", m.sr_rimasti("GER"), " pronti=", ia._pronti_a_est())
		var res := m.applica(ia.decidi(r))
		if not res["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if m.s["pot"]["GER"]["guerra"].has("URSS"): break
	quit()
