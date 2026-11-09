extends SceneTree
## Prova dell'interfaccia: un turno dell'Asse giocato "a mano" con le funzioni dei pannelli.
var main
func _initialize():
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()
func _run():
	for i in 5: await process_frame
	main.modo = "base"
	main._nuova_partita({"asse": true, "alleati": false})
	await main._decidi({"t": "fine"})                 # nessuna dichiarazione
	await main._decidi({"t": "opz", "p": "GER", "o": "off"})
	print("fase: ", main.m.richiesta())
	# muove la prima unità tedesca mobile con un clic sull'esagono e uno sulla destinazione
	var mossa := false
	for uid in main.m.s["u"]:
		var u = main.m.s["u"][uid]
		if u["n"] == "GER" and u["t"] == "fan" and main.m.raggiungibili(uid).size() > 0:
			main._clic_esagono(u["h"])
			await process_frame
			var dest = main.m.raggiungibili(main.sel_unita).keys()[0]
			await main._clic_movimento(dest, false)
			print("mossa ", uid, " -> ", main.m.s["u"][uid]["h"] if main.m.s["u"].has(uid) else "?")
			mossa = true
			break
	await main._decidi({"t": "fine"})
	print("fase: ", main.m.richiesta())
	var b: Array = main._bersagli(false)
	print("bersagli: ", b.size())
	if b.size() > 0:
		main._prepara_attacco(b[0], false)
		await main._esegui_attacco()
		print("attacco eseguito, popup: ", main.popup.visible)
		main._chiudi_popup()
	var r = main.m.richiesta()
	if r["k"] == "avanzata":
		main._aggiorna()
		await main._decidi({"t": "avanza", "u": r["u"].slice(0, 2)})
	await main._decidi({"t": "fine"})   # fine combattimento
	print("fase: ", main.m.richiesta())
	if main.m.richiesta()["k"] == "sfruttamento":
		await main._decidi({"t": "fine"})
	# costruzione: sceglie una fanteria e la piazza
	main._aggiorna()
	main._scegli_costruzione("GER", ["fan", 3, 3])
	var luoghi = main.m.luoghi_costruzione("GER", "fan")
	if luoghi.size() > 0:
		await main._clic_esagono(luoghi[0])
	print("BRP GER dopo costruzione: ", main.m.s["pot"]["GER"]["brp"])
	await main._decidi({"t": "fine"})
	await main._decidi({"t": "fine"})
	print("dopo il turno: ", main.m.richiesta(), " lato ", main.m.s["lato"])
	# lascia giocare l'IA alleata
	var k := 0
	while not main.umani.get(main.m.richiesta()["g"], false) and k < 3000:
		main._passo_ia(main.m.richiesta())
		k += 1
	print("di nuovo all'Asse: ", main.m.data_testo(), " ", main.m.richiesta())
	main._apri_menu_partita()
	main._chiudi_popup()
	quit()
