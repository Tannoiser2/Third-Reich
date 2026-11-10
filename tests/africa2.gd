extends SceneTree
## Andamento della campagna del deserto: chi tiene i capisaldi della strada costiera, stagione per stagione
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1], int(args[0]))
	var ia := IA.new(m)
	var turno := -1
	var passi := 0
	var att := 0
	m.evento.connect(func(t):
		if t.begins_with("Attacco su"):
			var id: String = t.get_slice("(", 1).get_slice(")", 0) if t.contains("(") else t.get_slice(" ", 2).get_slice(":", 0)
			if m.D.esagoni.has(id) and m.D.esagoni[id]["n"] in IA.AFRICA:
				att += 1)
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		if not m.applica(ia.decidi(r))["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if int(m.s["turno"]) != turno:
			turno = int(m.s["turno"])
			var riga := ""
			for id in IA.CATENA_AFRICA:
				var l := m.lato(m.controllo(id))
				riga += ("A" if l == "asse" else ("a" if l == "alleati" else "."))
			var fa := ia._forze_africa()
			print(m.data_testo(), " ", riga, "  asse=", fa["asse"], " alleati=", fa["alleati"], " ob asse=", ia.obiettivo_deserto("asse"), " ob alleati=", ia.obiettivo_deserto("alleati"), " attacchi=", att)
	quit()
