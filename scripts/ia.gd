## Intelligenza artificiale per uno schieramento (o per entrambi, in una partita dimostrativa).
## Restituisce una decisione alla volta per la richiesta corrente del motore.
## Movimenti e ridispiegamenti si pianificano una volta per fase; gli attacchi uno alla volta,
## perché ogni risultato cambia la situazione.
class_name IA
extends RefCounted

var m: Motore
var D: Dati
var _piano := []
var _piano_chiave := ""
var _fronte := {}
var _fronte_chiave := ""

func _init(motore: Motore) -> void:
	m = motore
	D = motore.D

func decidi(r: Dictionary) -> Dictionary:
	match r.get("k", ""):
		"diplomazia":
			return _diplomazia(r)
		"dichiarazioni":
			return _dichiarazioni()
		"opzioni":
			return _opzione(r["p"])
		"movimento":
			return _dal_piano("mov", func(): return _piano_movimento(false))
		"combattimento":
			return _combattimento(false)
		"avanzata":
			return _avanzata(r)
		"sfruttamento":
			var a := _combattimento(true)
			if a.get("t", "") == "attacca":
				return a
			return _dal_piano("sfr", func(): return _piano_movimento(true))
		"costruzione":
			return _dal_piano("cos", func(): return _piano_costruzione())
		"ridispiegamento":
			return _dal_piano("sr", func(): return _piano_sr())
	return {"t": "fine"}

func _dal_piano(tipo: String, crea: Callable) -> Dictionary:
	var chiave := "%s|%d|%s|%s" % [tipo, int(m.s["turno"]), m.s["lato"], m.s["fase"]]
	if chiave != _piano_chiave:
		_piano_chiave = chiave
		_piano = crea.call()
	while _piano.size() > 0:
		var d: Dictionary = _piano.pop_front()
		# controlla che la decisione sia ancora valida
		match d["t"]:
			"muovi":
				var sf: bool = m.s["fase"] == "sfruttamento"
				if m.s["u"].has(d["u"]) and m.raggiungibili(d["u"], sf).has(d["h"]):
					return d
			"sr":
				if m.destinazioni_sr(d["u"]).has(d["h"]):
					return d
			"costruisci_ia":
				var x := risolvi(d)
				if x["t"] == "costruisci" and int(m.s["pot"][x["p"]]["brp"]) >= m.costo_unita(m.s["pool"][x["p"]][x["i"]]) and m.luoghi_costruzione(x["p"], m.s["pool"][x["p"]][x["i"]][0]).has(x["h"]):
					return x
			_:
				return d
	if tipo == "sfr":
		_piano_chiave = ""
	return {"t": "fine"}

# -------------------------------------------------------------------------------------
# Diplomazia e dichiarazioni
# -------------------------------------------------------------------------------------

func _diplomazia(r: Dictionary) -> Dictionary:
	if int(r["dp"]) <= 0:
		return {"t": "fine"}
	var pref := ["RUM", "HUN", "BUL", "FIN", "SPA", "TUR", "SWE", "JUG"] if r["g"] == "asse" else ["TUR", "SPA", "GRE", "JUG", "SWE", "PER", "POR"]
	var b: Array = r["bersagli"]
	# concentra i punti sui primi due bersagli disponibili
	var scelti := []
	for x in pref:
		if b.has(x):
			scelti.append(x)
		if scelti.size() >= 2:
			break
	if scelti.is_empty():
		return {"t": "fine"}
	var dp: Dictionary = m.s.get("dp", {})
	var migliore: String = scelti[0]
	if scelti.size() > 1 and int(dp.get(scelti[0], {}).get(r["g"], 0)) >= 3:
		migliore = scelti[1]
	return {"t": "dp", "c": migliore}

func _dichiarazioni() -> Dictionary:
	var l: String = m.s["lato"]
	var anno := int(m.s["anno"])
	var st := int(m.s["stag"])
	var t := anno * 4 + st
	for p in m.potenze_del_lato(l):
		var poss := m.dichiarazioni_possibili(p)
		if poss.is_empty():
			continue
		var brp := int(m.s["pot"][p]["brp"])
		var voglio := []
		match p:
			"GER":
				if t >= 1940 * 4 + 0:
					voglio.append_array(["DAN", "NOR", "NED", "BEL", "LUX"])
				if t >= 1941 * 4 + 0:
					voglio.append_array(["JUG", "GRE"])
				if t >= 1941 * 4 + 1 and brp >= 35 + 15 and _pronti_a_est():
					voglio.append("URSS")
			"ITA":
				if t >= 1940 * 4 + 1 or m.s["pot"]["FRA"]["arresa"]:
					voglio.append("FRA" if not m.s["pot"]["FRA"]["arresa"] else "GB")
				if t >= 1940 * 4 + 2:
					voglio.append("GRE")
			"GB", "USA":
				if t >= 1942 * 4 + 2 and m.attiva("USA"):
					voglio.append("VIC")
			"URSS":
				if t >= 1942 * 4 + 0:
					voglio.append("GER")
		for c in voglio:
			if poss.has(c):
				var costo := Dati.COSTO_GUERRA_MAGGIORE if m.maggiore(c) else Dati.COSTO_GUERRA_MINORE
				if brp - costo >= 15:
					return {"t": "dichiara", "p": p, "c": c}
	return {"t": "fine"}

# -------------------------------------------------------------------------------------
# Opzioni
# -------------------------------------------------------------------------------------

func _opzione(p: String) -> Dictionary:
	var brp := int(m.s["pot"][p]["brp"])
	var contatto := false
	var buona := false
	var vuoti := false
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.comandante(u["n"]) != p or not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		for v in D.esagoni[u["h"]]["vicini"]:
			var dif := m.terrestri_in(v)
			var nem := false
			for x in dif:
				if m.in_guerra(u["n"], m.s["u"][x]["n"]):
					nem = true
			if nem:
				contatto = true
				# stima rozza: somma dei nostri fattori adiacenti
				var fa := 0
				for w in D.esagoni[v]["vicini"]:
					for y in m.terrestri_in(w):
						if m.comandante(m.s["u"][y]["n"]) == p:
							fa += m.forza(y)
				var fd := 0
				for x in dif:
					fd += m.forza(x)
				if D.esagoni[v]["t"] != 0:
					fd *= 2
				var serve := 2
				if p in ["GB", "FRA"] and int(m.s["anno"]) <= 1941:
					serve = 3
				if fa >= fd * serve:
					buona = true
			elif dif.is_empty():
				var c := m.controllo(v)
				if c != "" and m.in_guerra(p, c):
					vuoti = true
	var costo := m.costo_offensiva(p)
	if not m.offensiva_permessa(p):
		buona = false
		vuoti = false
	# l'URSS resta sulla difensiva nel primo inverno solo se non ha attacchi buoni
	if (buona or vuoti) and brp >= costo:
		return {"t": "opz", "p": p, "o": "off"}
	if contatto:
		return {"t": "opz", "p": p, "o": "log"}
	# territori nemici da raggiungere: offensiva se ci sono unità vicine al confine e BRP abbondanti
	if brp >= costo + 30 and m.offensiva_permessa(p) and _vicini_al_nemico(p):
		return {"t": "opz", "p": p, "o": "off"}
	return {"t": "opz", "p": p, "o": "pas"}

func _pronti_a_est() -> bool:
	var vicini := 0
	var tot := 0
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) != "asse" or not Motore._terrestre(u["t"]):
			continue
		tot += m.forza(uid)
		var vicino := false
		for v in D.esagoni[u["h"]]["vicini"]:
			if m.controllo(v) == "URSS":
				vicino = true
		if not vicino:
			for v in D.esagoni[u["h"]]["vicini"]:
				for w in D.esagoni[v]["vicini"]:
					if m.controllo(w) == "URSS":
						vicino = true
		if vicino:
			vicini += m.forza(uid)
	return tot > 0 and vicini * 2 >= tot

func _vicini_al_nemico(p: String) -> bool:
	var f := _distanza_fronte(m.lato(p))
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.comandante(u["n"]) == p and Motore._terrestre(u["t"]) and u["h"] != "USA" and int(f.get(u["h"], 99)) <= 3:
			return true
	return false

# -------------------------------------------------------------------------------------
# Distanza dal fronte
# -------------------------------------------------------------------------------------

## distanza (in esagoni di terra) dal territorio nemico più vicino, per lo schieramento l
func _distanza_fronte(l: String) -> Dictionary:
	var chiave := "%s|%d" % [l, int(m.s["prog"])]
	if chiave == _fronte_chiave:
		return _fronte
	var dist := {}
	var coda := []
	for id in m.s["ctrl"]:
		var c: String = m.s["ctrl"][id]
		var lc := m.lato(c)
		if lc == "" or lc == l:
			continue
		var nemico := false
		for p in m.potenze_del_lato(l):
			if m.in_guerra(p, c):
				nemico = true
		if not nemico and l == "asse" and lc == "alleati" and c == "URSS" and _prepara_barbarossa():
			nemico = true
		if not nemico:
			continue
		dist[id] = 0
		coda.append(id)
	var i := 0
	while i < coda.size():
		var a: String = coda[i]
		i += 1
		for b in D.esagoni[a]["vicini"]:
			if not D.terra(b) or dist.has(b):
				continue
			dist[b] = int(dist[a]) + 1
			coda.append(b)
	_fronte = dist
	_fronte_chiave = chiave
	return dist

## la Germania sposta le forze a est prima di attaccare l'URSS
func _prepara_barbarossa() -> bool:
	var a := int(m.s["anno"])
	return a >= 1941 and not m.s["pot"]["GER"]["guerra"].has("URSS") and m.s["pot"]["FRA"]["arresa"]

func _forza_nemica_vicina(id: String, n: String, raggio := 2) -> int:
	var tot := 0
	var visti := {id: 0}
	var coda := [id]
	var i := 0
	while i < coda.size():
		var a: String = coda[i]
		i += 1
		if int(visti[a]) >= raggio:
			continue
		for b in D.esagoni[a]["vicini"]:
			if visti.has(b):
				continue
			visti[b] = int(visti[a]) + 1
			coda.append(b)
			for x in m.terrestri_in(b):
				if m.in_guerra(n, m.s["u"][x]["n"]):
					tot += m.forza(x)
	return tot

func _importanza(id: String) -> float:
	var h: Dictionary = D.esagoni[id]
	var v := 0.0
	var tipo: String = h["tipo"]
	if h["citta"] != "":
		v += 2.0
	if tipo.contains("O"):
		v += 6.0
	if tipo.contains("C"):
		v += 6.0
	if tipo.contains("I"):
		v += 3.0
	return v

# -------------------------------------------------------------------------------------
# Movimento
# -------------------------------------------------------------------------------------

func _piano_movimento(sfruttamento: bool) -> Array:
	var l: String = m.s["lato"]
	var piano := []
	var fronte := _distanza_fronte(l)
	var unita := []
	for uid in m.s["u"]:
		if m.puo_muovere(uid, sfruttamento):
			unita.append(uid)
	# corazzati per primi, poi la fanteria più forte
	unita.sort_custom(func(a, b): return _priorita(a) > _priorita(b))
	var presi := {}   # esagono -> unità previste
	var difesa := {}  # esagoni di fronte già coperti
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) == l and Motore._terrestre(u["t"]):
			difesa[u["h"]] = int(difesa.get(u["h"], 0)) + 1
	for uid in unita:
		var u: Dictionary = m.s["u"][uid]
		var dec := {}
		match u["t"]:
			"avi":
				dec = _muovi_aereo(uid, fronte)
			"flo":
				dec = {}
			_:
				dec = _muovi_terrestre(uid, fronte, presi, difesa, sfruttamento)
		if dec.is_empty():
			continue
		piano.append(dec)
		if Motore._terrestre(u["t"]):
			presi[dec["h"]] = int(presi.get(dec["h"], 0)) + 1
			difesa[u["h"]] = int(difesa.get(u["h"], 1)) - 1
			difesa[dec["h"]] = int(difesa.get(dec["h"], 0)) + 1
	if not sfruttamento:
		piano = _presidi(piano, difesa, fronte, l)
	return piano

## le capitali e gli obiettivi della propria patria vicini al nemico non restano vuoti
func _presidi(piano: Array, difesa: Dictionary, fronte: Dictionary, l: String) -> Array:
	var mosse := {}
	for d in piano:
		mosse[d["u"]] = d
	var lista: Array = D.obiettivi + D.capitali.values()
	for id in lista:
		if id == "" or not D.esagoni.has(id):
			continue
		var c := m.controllo(id)
		if m.lato(c) != l or not m.maggiore(c) or D.esagoni[id]["n"] != c:
			continue
		var limite := 5
		if str(D.esagoni[id]["tipo"]).contains("C"):
			limite = 12
		if int(fronte.get(id, 99)) > limite or int(difesa.get(id, 0)) > 0:
			continue
		# l'unità più vicina che può arrivarci
		var migliore := ""
		var md := 999
		for uid in m.s["u"]:
			var u: Dictionary = m.s["u"][uid]
			if m.lato(u["n"]) != l or not Motore._terrestre(u["t"]) or not m.puo_muovere(uid):
				continue
			if int(difesa.get(u["h"], 0)) <= 1 and int(fronte.get(u["h"], 99)) <= 1:
				continue
			var rr := m.raggiungibili(uid)
			if rr.has(id) and int(rr[id]) >= 0 and int(rr[id]) < md:
				md = int(rr[id])
				migliore = uid
		if migliore != "":
			if mosse.has(migliore):
				piano.erase(mosse[migliore])
			var dec := {"t": "muovi", "u": migliore, "h": id}
			piano.push_front(dec)
			mosse[migliore] = dec
			difesa[id] = 1
	return piano

func _priorita(uid: String) -> float:
	var u: Dictionary = m.s["u"][uid]
	var k := {"cor": 3.0, "par": 2.0, "fan": 1.0, "rim": 0.5, "avi": 0.1, "flo": 0.0}
	return k.get(u["t"], 0.0) * 10.0 + float(u["a"])

func _muovi_terrestre(uid: String, fronte: Dictionary, presi: Dictionary, difesa: Dictionary, sfruttamento: bool) -> Dictionary:
	var u: Dictionary = m.s["u"][uid]
	var n: String = u["n"]
	var off := m.opzione(n) == "off"
	var qui: String = u["h"]
	var rr := m.raggiungibili(uid, sfruttamento)
	if rr.is_empty():
		return {}
	var d_qui := int(fronte.get(qui, 99))
	# valore del restare: alto se l'esagono è sul fronte e importante
	var best := ""
	var best_v := _valore_posizione(qui, n, off, fronte, difesa, true, uid)
	for id in rr:
		if int(presi.get(id, 0)) + m.terrestri_in(id).size() >= 2:
			continue
		var v := _valore_posizione(id, n, off, fronte, difesa, false, uid)
		if int(rr[id]) == -1:
			# via mare: l'IA sbarca solo in territorio amico o con un'invasione alleata dal 1943
			var amica := m.lato(m.controllo(id)) == m.lato(n)
			if not amica and not (m.lato(n) == "alleati" and int(m.s["anno"]) >= 1943 and _vicino_a_amici(id, n)):
				continue
			v -= 4.0
			if int(fronte.get(id, 99)) > d_qui and m.controllo(id) != "" and m.lato(m.controllo(id)) == m.lato(n):
				v -= 10.0
		if v > best_v + 0.01:
			best_v = v
			best = id
	if best == "":
		return {}
	return {"t": "muovi", "u": uid, "h": best}

func _vicino_a_amici(id: String, n: String) -> bool:
	for v in D.esagoni[id]["vicini"]:
		for x in m.terrestri_in(v):
			if m.lato(m.s["u"][x]["n"]) == m.lato(n):
				return true
	return false

func _valore_posizione(id: String, n: String, off: bool, fronte: Dictionary, difesa: Dictionary, resto: bool, uid: String) -> float:
	var d := int(fronte.get(id, 60))
	var v := -float(d) * 1.5
	var c := m.controllo(id)
	var lc := m.lato(c)
	var mio := lc == m.lato(n)
	# conquista di un esagono nemico vuoto
	if not mio and lc != "":
		v += 4.0 + _importanza(id) * 1.5
	# posizione d'attacco: adiacente a unità nemiche
	if off:
		var debole := 999
		for w in D.esagoni[id]["vicini"]:
			var fd := 0
			var nem := false
			for x in m.terrestri_in(w):
				if m.in_guerra(n, m.s["u"][x]["n"]):
					nem = true
					fd += m.forza(x)
			if nem:
				if D.esagoni[w]["t"] != 0:
					fd *= 2
				debole = mini(debole, fd)
				v += _importanza(w) * 0.3
		if debole < 999:
			v += 6.0 - float(debole) * 0.4
	# difesa del fronte: copertura degli esagoni a contatto
	if mio and d <= 1:
		var minaccia := _forza_nemica_vicina(id, n, 2)
		var gia := int(difesa.get(id, 0)) - (1 if resto else 0)
		if minaccia > 0:
			v += (3.0 if gia <= 0 else (1.0 if gia == 1 else -2.0)) + _importanza(id) * 0.5 + minaccia * 0.05
			if D.esagoni[id]["t"] != 0:
				v += 1.0
	if resto:
		v += 0.5
	# non lasciare la capitale scoperta
	if resto and str(D.esagoni[id]["tipo"]).contains("C") and d <= 2 and int(difesa.get(id, 0)) <= 1:
		v += 8.0
	return v

func _muovi_aereo(uid: String, fronte: Dictionary) -> Dictionary:
	var u: Dictionary = m.s["u"][uid]
	var qui: String = u["h"]
	var rr := m.raggiungibili(uid)
	var best := ""
	var bd := int(fronte.get(qui, 99)) if qui != "USA" else 99
	if bd >= 2 and bd <= 3:
		return {}
	for id in rr:
		var d := int(fronte.get(id, 99))
		if d < 2:
			continue
		var score := absi(d - 2)
		if best == "" or score < absi(bd - 2):
			best = id
			bd = d
	if best == "":
		return {}
	return {"t": "muovi", "u": uid, "h": best}

# -------------------------------------------------------------------------------------
# Combattimento
# -------------------------------------------------------------------------------------

func _combattimento(sfruttamento: bool) -> Dictionary:
	var l: String = m.s["lato"]
	var bersagli := {}
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) != l or not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		for v in D.esagoni[u["h"]]["vicini"]:
			bersagli[v] = true
	var migliore := {}
	var mv := -999.0
	for b in bersagli:
		var att := m.attaccanti_possibili(b, sfruttamento)
		if att.is_empty():
			continue
		var piano := _piano_attacco(b, att, l)
		if piano.is_empty():
			continue
		if float(piano["v"]) > mv:
			mv = piano["v"]
			migliore = piano
	if migliore.is_empty():
		if sfruttamento:
			return {}
		return {"t": "fine"}
	return {"t": "attacca", "h": migliore["h"], "u": migliore["u"], "av": migliore["av"]}

func _piano_attacco(b: String, att0: Array, l: String) -> Dictionary:
	var att := att0
	if not m.cooperazione_ok(att):
		var gb := []
		var fr := []
		for uid in att:
			if m.comandante(m.s["u"][uid]["n"]) == "GB":
				gb.append(uid)
			else:
				fr.append(uid)
		var fg := 0
		var ff := 0
		for uid in gb:
			fg += m.forza(uid)
		for uid in fr:
			ff += m.forza(uid)
		att = gb if fg > ff else fr
	var ordinati := att.duplicate()
	ordinati.sort_custom(func(x, y): return m.forza(x) > m.forza(y))
	var aerei := m.aerei_possibili(b, l)
	aerei.sort_custom(func(x, y): return m.forza(x) > m.forza(y))
	var scelti := []
	var av := []
	var v := {}
	# tutte le unità di terra disponibili
	for uid in ordinati:
		scelti.append(uid)
	v = m.valuta_attacco(b, scelti, av)
	var obiettivo := 5 if int(v["base"]) >= 4 else 4
	for uid in aerei:
		if int(v["col"]) >= obiettivo + 1:
			break
		av.append(uid)
		v = m.valuta_attacco(b, scelti, av)
	# togli le unità superflue (le più deboli) se il rapporto resta uguale
	var col := int(v["col"])
	var i := scelti.size() - 1
	while i > 0 and col >= 0:
		var prova := scelti.duplicate()
		prova.remove_at(i)
		var v2 := m.valuta_attacco(b, prova, av)
		if int(v2["col"]) >= col:
			scelti = prova
			v = v2
		i -= 1
	col = int(v["col"])
	var imp := _importanza(b)
	var soglia := 4
	if imp >= 6.0 or int(v["base"]) <= 2:
		soglia = 4
	if int(v["base"]) >= 6 and imp < 6.0:
		soglia = 5
	if col < soglia:
		return {}
	var valore := float(col) * 3.0 + imp + float(v["base"]) * 0.5
	return {"h": b, "u": scelti, "av": av, "v": valore}

func _avanzata(r: Dictionary) -> Dictionary:
	var lista: Array = r["u"]
	var scelti := []
	var ordinati := lista.duplicate()
	ordinati.sort_custom(func(a, b): return _priorita(a) > _priorita(b))
	for uid in ordinati:
		if scelti.size() >= 2:
			break
		scelti.append(uid)
	return {"t": "avanza", "u": scelti}

# -------------------------------------------------------------------------------------
# Costruzione e ridispiegamento
# -------------------------------------------------------------------------------------

func _piano_costruzione() -> Array:
	var piano := []
	var l: String = m.s["lato"]
	var fronte := _distanza_fronte(l)
	for p in m.costruttori():
		var brp := int(m.s["pot"][p]["brp"])
		var riserva := 15
		if p == "GER" and int(m.s["anno"]) <= 1941 and not m.s["pot"]["GER"]["guerra"].has("URSS"):
			riserva = 50
		if p == "ITA" and not m.attiva("ITA"):
			riserva = 50
		var pool: Array = m.s["pool"][p].duplicate()
		var usati := {}
		var posti_usati := {}
		var giri := 0
		while giri < 40:
			giri += 1
			var scelta := -1
			var miglior_v := -1.0
			for i in pool.size():
				if usati.has(i):
					continue
				var e: Array = pool[i]
				var c := m.costo_unita(e)
				if brp - c < riserva:
					continue
				var val := _valore_unita(e, p, brp - riserva)
				if val > miglior_v:
					miglior_v = val
					scelta = i
			if scelta < 0:
				break
			var e: Array = pool[scelta]
			var luoghi := m.luoghi_costruzione(p, e[0])
			var dove := ""
			var bd := 999
			for id in luoghi:
				if Motore._terrestre(e[0]) and int(posti_usati.get(id, 0)) + m.terrestri_in(id).size() >= 2:
					continue
				var d := int(fronte.get(id, 50))
				if Motore._terrestre(e[0]) and d == 0:
					continue
				if d < bd:
					bd = d
					dove = id
			if dove == "":
				usati[scelta] = true
				continue
			usati[scelta] = true
			brp -= m.costo_unita(e)
			posti_usati[dove] = int(posti_usati.get(dove, 0)) + 1
			# l'indice nel pool cambia man mano che si costruisce: lo si ricalcola al momento
			piano.append({"t": "costruisci", "p": p, "e": e, "h": dove})
	# converte in decisioni con l'indice attuale
	var out := []
	for d in piano:
		out.append(d)
	return _con_indici(out)

func _con_indici(lista: Array) -> Array:
	# l'indice viene trovato al momento dell'esecuzione (vedi _risolvi_costruzione)
	var out := []
	for d in lista:
		out.append({"t": "costruisci_ia", "p": d["p"], "e": d["e"], "h": d["h"]})
	return out

## trasforma una decisione di costruzione pianificata nell'indice corretto del pool
func risolvi(d: Dictionary) -> Dictionary:
	if d.get("t", "") != "costruisci_ia":
		return d
	var pool: Array = m.s["pool"][d["p"]]
	for i in pool.size():
		var e: Array = pool[i]
		if str(e[0]) == str(d["e"][0]) and int(e[1]) == int(d["e"][1]) and int(e[2]) == int(d["e"][2]):
			return {"t": "costruisci", "p": d["p"], "i": i, "h": d["h"]}
	return {"t": "fine_parziale"}

func _valore_unita(e: Array, p: String, budget: int) -> float:
	var t: String = e[0]
	var a := int(e[1])
	var c := m.costo_unita(e)
	match t:
		"cor":
			return 5.0 + a
		"fan":
			return 3.0 + a
		"rim":
			return 1.0
		"par":
			return 1.5
		"avi":
			return 2.0 if budget >= 60 else -1.0
		"flo":
			return 0.5 if budget >= 80 and p in ["GB", "USA"] else -1.0
	return 0.0 - c * 0.01

func _piano_sr() -> Array:
	var piano := []
	var l: String = m.s["lato"]
	var fronte := _distanza_fronte(l)
	var arrivi := {}
	for p in m.potenze_del_lato(l):
		var n_sr := m.sr_rimasti(p)
		if n_sr <= 0:
			continue
		var cand := []
		for uid in m.s["u"]:
			var u: Dictionary = m.s["u"][uid]
			if m.comandante(u["n"]) != p or not m.maggiore(u["n"]) or not Motore._terrestre(u["t"]):
				continue
			var d := int(fronte.get(u["h"], 99)) if u["h"] != "USA" else 99
			if d >= 4:
				cand.append(uid)
		cand.sort_custom(func(a, b): return _priorita(a) > _priorita(b))
		for uid in cand:
			if n_sr <= 0:
				break
			var dest := m.destinazioni_sr(uid)
			var best := ""
			var bv := -999.0
			var u: Dictionary = m.s["u"][uid]
			var d0 := int(fronte.get(u["h"], 99)) if u["h"] != "USA" else 99
			for id in dest:
				if int(arrivi.get(id, 0)) + m.terrestri_in(id).size() >= 2:
					continue
				var d := int(fronte.get(id, 99))
				if d < 1 or d >= d0:
					continue
				var v := -float(d) * 2.0 + _importanza(id) * 0.3 + float(_forza_nemica_vicina(id, u["n"], 3)) * 0.05
				if v > bv:
					bv = v
					best = id
			if best != "":
				piano.append({"t": "sr", "u": uid, "h": best})
				arrivi[best] = int(arrivi.get(best, 0)) + 1
				n_sr -= 1
	return piano
