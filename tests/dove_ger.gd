extends SceneTree
## Dove sono le forze tedesche quando inizia Barbarossa
func _initialize():
	var args := OS.get_cmdline_user_args()
	var m := Motore.new()
	m.nuova(args[1], int(args[0]))
	var ia := IA.new(m)
	var passi := 0
	while not m.finita() and passi < 200000:
		var r := m.richiesta()
		if not m.applica(ia.decidi(r))["ok"]:
			m.applica({"t": "fine"})
		passi += 1
		if m.s["pot"]["GER"]["guerra"].has("URSS") and m.s["fase"] == "movimento":
			break
	var reg := {}
	var tot := 0
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if u["n"] != "GER" or not Motore._terrestre(u["t"]) or u["h"] == "USA": continue
		var e: Dictionary = m.D.esagoni[u["h"]]
		var k: String = e["n"]
		if k == "GER":
			k = "GER-ovest" if int(e["c"]) < 30 else "GER-est"
		var cell: String = k + ("*" if ia._guarnigioni_vallo().has(uid) or ia._guarnigioni_capitali("asse").has(uid) else "")
		reg[cell] = int(reg.get(cell, 0)) + m.forza(uid)
		tot += m.forza(uid)
	print(m.data_testo(), " totale tedesco=", tot, " ", reg)
	quit()
