extends SceneTree
## Dopo Barbarossa: dove stanno le unità dell'Asse e quanto distano dal fronte, all'inizio del movimento tedesco
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1], int(args[0]))
	var ia := IA.new(m)
	var passi := 0
	var visti := 0
	var ultimo := ""
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		if m.s["pot"]["GER"]["guerra"].has("URSS") and r["k"] == "movimento" and m.s["lato"] == "asse" and m.data_testo() != ultimo:
			ultimo = m.data_testo()
			visti += 1
			var fronte := ia._distanza_da(["URSS"])
			var fasce := {}
			var lontani := {}
			for uid in m.s["u"]:
				var u: Dictionary = m.s["u"][uid]
				if m.lato(u["n"]) != "asse" or not Motore._terrestre(u["t"]) or u["h"] == "USA": continue
				var d := int(fronte.get(u["h"], 99))
				var k := "est 0-1" if d <= 1 else ("est 2-3" if d <= 3 else ("est 4-6" if d <= 6 else "lontano"))
				fasce[k] = int(fasce.get(k, 0)) + m.forza(uid)
				if d >= 7:
					var naz: String = m.D.esagoni[u["h"]]["n"]
					var chiave := "%s/%s" % [u["n"], naz]
					lontani[chiave] = int(lontani.get(chiave, 0)) + m.forza(uid)
			print(ultimo, " fattori per distanza dal fronte: ", fasce, "  lontani: ", lontani)
			if visti >= 3: break
		if not m.applica(ia.decidi(r))["ok"]:
			m.applica({"t": "fine"})
		passi += 1
	quit()
