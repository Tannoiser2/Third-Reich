extends SceneTree
## Chi prende Berlino e quando
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1], int(args[0]))
	var ia := IA.new(m)
	var passi := 0
	var prima := m.controllo("L31")
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		var d := ia.decidi(r)
		var res := m.applica(d)
		if not res["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		var ora := m.controllo("L31")
		if ora != prima:
			var chi := []
			for x in m.terrestri_in("L31"):
				chi.append("%s %s" % [m.s["u"][x]["n"], m.s["u"][x]["t"]])
			print(m.data_testo(), " ", m.s["lato"], " fase=", m.s["fase"], " Berlino: ", prima, " -> ", ora, " decisione=", d, " in Berlino: ", chi)
			prima = ora
	quit()
