extends SceneTree
## Diagnosi: per ogni turno, attacchi tedeschi e BRP fino all'estate 1942
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1] if args.size() > 1 else "base", int(args[0]) if args.size() > 0 else 3)
	var ia := IA.new(m)
	var att := {}
	m.evento.connect(func(t): if t.begins_with("Attacco") and m.s["lato"] == "asse": att[m.data_testo()] = int(att.get(m.data_testo(), 0)) + 1)
	var turno := -1
	while not m.finita() and int(m.s["anno"]) <= 1941:
		var r := m.richiesta()
		if r["k"] == "dichiarazioni" and m.s["lato"] == "asse" and int(m.s["turno"]) != turno:
			turno = int(m.s["turno"])
			var ger := 0
			var fra := 0
			var fra_f := 0
			var ovest := 0
			for uid in m.s["u"]:
				var u = m.s["u"][uid]
				if u["n"] == "GER" and Motore._terrestre(u["t"]):
					ger += 1
				if (u["n"] == "FRA" or u["n"] == "GB") and Motore._terrestre(u["t"]) and m.D.esagoni.has(u["h"]) and m.D.esagoni[u["h"]]["n"] in ["FRA", "BEL", "NED"]:
					fra += 1
					fra_f += int(u["a"])
			print("%s GER brp=%d unità=%d | Alleati in Francia %d unità %d fattori, FRA brp %d %s" % [m.data_testo(), m.s["pot"]["GER"]["brp"], ger, fra, fra_f, m.s["pot"]["FRA"]["brp"], "resa" if m.s["pot"]["FRA"]["arresa"] else ""])
		var d := ia.decidi(r)
		if not m.applica(d)["ok"]:
			m.applica({"t": "fine"})
	for k in att: print(k, ": ", att[k], " attacchi tedeschi")
	quit()
