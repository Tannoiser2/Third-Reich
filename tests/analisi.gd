extends SceneTree
func _initialize():
	var m := Motore.new()
	var st = JSON.parse_string(FileAccess.open("/tmp/dump.json", FileAccess.READ).get_as_text())
	m.importa(st)
	var ia := IA.new(m)
	print(m.data_testo(), " fase ", m.s["fase"], " lato ", m.s["lato"], " opz GER ", m.s["pot"]["GER"]["opz"])
	var bers := {}
	for uid in m.s["u"]:
		var u = m.s["u"][uid]
		if m.lato(u["n"]) != "asse" or not Motore._terrestre(u["t"]): continue
		for v in m.D.esagoni[u["h"]]["vicini"]:
			bers[v] = true
	for b in bers:
		var att := m.attaccanti_possibili(b)
		if m.terrestri_in(b).is_empty(): continue
		var all_air := m.aerei_possibili(b, "asse")
		var v := m.valuta_attacco(b, att, all_air)
		print(b, " dif=", m.terrestri_in(b).map(func(x): return m.descrizione_unita(x)), " att=", att.size(), " fa=", v["att"], " fd=", v["dif"], " col=", v["col"], " ", v["motivo"], " piano=", ia._piano_attacco(b, att, "asse"))
	quit()
