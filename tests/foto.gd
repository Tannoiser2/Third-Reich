extends SceneTree
## Screenshot dell'interfaccia: xvfb-run godot --path . -s res://tests/foto.gd -- <modo> [passi]
var main
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()
func shot(nome: String):
	for i in 20: await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/shot_%s.png" % nome)
	print("shot ", nome)
func _run():
	var args := OS.get_cmdline_user_args()
	var modo: String = args[0] if args.size() > 0 else "menu"
	await shot("menu")
	if modo == "menu":
		quit(); return
	main.modo = "advanced"
	main._nuova_partita({"asse": true, "alleati": false})
	await shot("inizio")
	var passi := int(args[1]) if args.size() > 1 else 0
	if modo == "avanti":
		# l'IA gioca anche per l'Asse per qualche passo
		main.umani = {"asse": false, "alleati": false}
		main.velocita = 0.0
		var k := 0
		while k < passi and not main.m.finita():
			main._passo_ia(main.m.richiesta())
			k += 1
		main.umani = {"asse": true, "alleati": false}
		main.vista.aggiorna(main.m.s, false)
		main._aggiorna()
		await shot("avanti")
		if args.size() > 2:
			main.vista.bersaglio = main.vista.mondo(args[2])
			main.vista.distanza = 8
			main.vista.beccheggio = 60
			main._sopra_esagono(args[2])
			await shot("avanti_vicino")
			print(main._testo_esagono(args[2]))
	if modo == "attacco":
		# vai al combattimento della Germania e prepara un attacco
		main.m.applica({"t": "fine"})
		main.m.applica({"t": "opz", "p": "GER", "o": "off"})
		main.m.applica({"t": "opz", "p": "ITA", "o": "pas"})
		main.m.applica({"t": "fine"})
		var bers: Array = main._bersagli(false)
		if bers.size() > 0:
			main._prepara_attacco(bers[0], false)
			main.vista.centra_su(bers[0])
			main.vista.distanza = 12
		main._aggiorna()
		await shot("attacco")
	if modo == "prova":
		for n in ["JUG", "HUN", "RUM", "BUL", "FIN", "SWE", "TUR", "SPA"]:
			main.m._nuova_unita(n, "fan", 2 if n != "BUL" else 1, 3, ["L29", "L30", "M29", "M30", "N29", "N30", "O29", "O30"][["JUG", "HUN", "RUM", "BUL", "FIN", "SWE", "TUR", "SPA"].find(n)])
		main.vista.aggiorna(main.m.s, false)
		main.vista.bersaglio = main.vista.mondo("M30")
		main.vista.distanza = 9
		await shot("prova")
	if modo == "vicino":
		main.vista.bersaglio = main.vista.mondo("M33")
		main.vista.distanza = 9
		main.vista.beccheggio = 48
		main._seleziona_info("M32")
		main._clic_esagono("L32")
		await shot("vicino")
	quit()
