extends SceneTree
## Forze per teatro a ogni stagione: -- seme modo
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1] if args.size() > 1 else "base", int(args[0]) if args.size() > 0 else 3)
	var ia := IA.new(m)
	var D: Dati = m.D
	var turno := -1
	var passi := 0
	var OVEST := ["FRA", "BEL", "NED", "LUX", "VIC"]
	var EST := ["POL", "URSS", "ROM", "LIT", "LAT", "EST", "FIN", "UNG", "BUL", "JUG", "GRE", "CEC"]
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		if not m.applica(ia.decidi(r))["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if int(m.s["turno"]) != turno:
			turno = int(m.s["turno"])
			var c := {"vallo": 0, "ger_ovest": 0, "ger_est": 0, "ger_casa": 0, "ger_altro": 0, "allGB": 0, "urss": 0, "urss_fuori": 0, "ger_costa_ovest": 0}
			for uid in m.s["u"]:
				var u: Dictionary = m.s["u"][uid]
				var h: String = u["h"]
				if h == "USA" or not Motore._terrestre(u["t"]):
					continue
				var naz: String = D.esagoni[h]["n"]
				var f := m.forza(uid)
				if u["n"] == "GER":
					if naz in OVEST:
						c["ger_ovest"] += f
						if D.esagoni[h]["costa"]: c["ger_costa_ovest"] += f
						if h in ia.vallo_atlantico().slice(0, 9): c["vallo"] += 1
					elif naz in EST: c["ger_est"] += f
					elif naz == "GER": c["ger_casa"] += f
					else: c["ger_altro"] += f
				elif (u["n"] == "GB" or u["n"] == "USA") and naz == "GB":
					c["allGB"] += f
				elif u["n"] == "URSS":
					c["urss"] += f
					if naz != "URSS": c["urss_fuori"] += f
			print(m.data_testo(), " ", c, " brp GER=", m.s["pot"]["GER"]["brp"], " URSS=", m.s["pot"]["URSS"]["brp"])
		if turno > 22: break
	quit()
