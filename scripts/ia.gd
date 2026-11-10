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
				# come i giocatori esperti: Olanda e Danimarca subito dopo la Polonia, poi Belgio e Lussemburgo
				if t >= 1939 * 4 + 3 and m.s["min"]["POL"]["st"] == "conquistato":
					voglio.append_array(["NED", "DAN"])
				if t >= 1940 * 4 + 0:
					voglio.append_array(["BEL", "LUX", "NOR"])
				if t >= 1941 * 4 + 0:
					voglio.append_array(["JUG", "GRE"])
				# Barbarossa: dall'estate 1941, quando a est c'è una forza adeguata; comunque prima che attacchi l'URSS (1942)
				var pronta: bool = m.s["pot"]["FRA"]["arresa"] and _pronti_a_est()
				if t >= 1941 * 4 + 1 and brp >= 35 + 15 and (pronta or (t >= 1941 * 4 + 2 and _pronti_a_est()) or t >= 1941 * 4 + 3):
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
	# la Germania non spende in offensive i BRP che servono a dichiarare Barbarossa
	if p == "GER" and int(m.s["anno"]) == 1941 and m.s["pot"]["FRA"]["arresa"] and not m.s["pot"]["GER"]["guerra"].has("URSS") and brp - costo < 50:
		buona = false
		vuoti = false
	# l'URSS resta sulla difensiva nel primo inverno solo se non ha attacchi buoni
	if (buona or vuoti) and brp >= costo:
		return {"t": "opz", "p": p, "o": "off"}
	# sbarco pronto: truppe nei porti d'invasione
	if p in ["GB", "USA"] and _invasione_attiva() and brp >= costo:
		var pronte := 0
		for id in PORTI_INVASIONE:
			pronte += m.terrestri_in(id).size()
		if pronte >= 3:
			return {"t": "opz", "p": p, "o": "off"}
	if contatto:
		return {"t": "opz", "p": p, "o": "log"}
	# territori nemici da raggiungere: offensiva se ci sono unità vicine al confine e BRP abbondanti
	var margine := 10 if m.lato(p) == "asse" or int(m.s["anno"]) >= 1942 else 30
	var per_barbarossa: bool = p == "GER" and int(m.s["anno"]) == 1941 and not m.s["pot"]["GER"]["guerra"].has("URSS") and brp - costo < 50
	if brp >= costo + margine and m.offensiva_permessa(p) and _vicini_al_nemico(p) and not per_barbarossa:
		return {"t": "opz", "p": p, "o": "off"}
	return {"t": "opz", "p": p, "o": "pas"}

## pronti per Barbarossa: forze tedesche e alleate vicine al confine sovietico almeno pari al 70% di quelle sovietiche
func _pronti_a_est() -> bool:
	var d_est := _distanza_da(["URSS"])
	var d_asse := _distanza_da(["GER", "ITA", "HUN", "RUM", "FIN", "BUL"])
	var asse := 0
	var sov := 0
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		if m.lato(u["n"]) == "asse" and int(d_est.get(u["h"], 99)) <= 3:
			asse += m.forza(uid)
		elif u["n"] == "URSS" and int(d_asse.get(u["h"], 99)) <= 4:
			sov += m.forza(uid)
	return asse >= 20 and float(asse) >= float(sov) * 0.7

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
	var ost := ostili(l)
	for id in m.s["ctrl"]:
		var c: String = m.s["ctrl"][id]
		if not ost.has(c):
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
	var presi := {}   # esagono -> unità previste in arrivo
	var difesa := {}  # esagono -> unità presenti (dopo le mosse previste)
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) == l and Motore._terrestre(u["t"]):
			difesa[u["h"]] = int(difesa.get(u["h"], 0)) + 1
	var usate := {}
	if not sfruttamento:
		# 1. coprire i settori del fronte rimasti scoperti (anche verso i nemici potenziali)
		for dec in _copri_fronte(l, presi, difesa, usate):
			piano.append(dec)
		# 2. presidiare capitali e obiettivi vicini al nemico
		piano = _presidi(piano, difesa, fronte, l, usate)
		# 3. chi attacca dà il cambio in prima linea: le unità deboli arretrano, le forti avanzano
		for d in piano:
			usate[d["u"]] = true
		for dec in _cambio_in_linea(l, presi, difesa, usate):
			piano.append(dec)
		for d in piano:
			usate[d["u"]] = true
	if not sfruttamento and l == "alleati" and int(m.s["anno"]) >= 1943 and m.attiva("USA"):
		for dec in _sbarco(usate, presi):
			piano.append(dec)
			usate[dec["u"]] = true
	var ob := _assegna_obiettivi(l, unita, usate)
	for uid in unita:
		if usate.has(uid):
			continue
		var u: Dictionary = m.s["u"][uid]
		var dec := {}
		match u["t"]:
			"avi":
				dec = _muovi_aereo(uid, fronte)
			"flo":
				dec = _muovi_flotta(uid)
			_:
				dec = _muovi_terrestre(uid, fronte, presi, difesa, sfruttamento, ob.get(uid, ""))
		if dec.is_empty():
			continue
		piano.append(dec)
		if Motore._terrestre(u["t"]):
			presi[dec["h"]] = int(presi.get(dec["h"], 0)) + 1
			difesa[u["h"]] = int(difesa.get(u["h"], 1)) - 1
			difesa[dec["h"]] = int(difesa.get(dec["h"], 0)) + 1
	return piano

## porti britannici da cui partono gli sbarchi sulla Manica
const PORTI_INVASIONE := ["L22", "K21", "K24", "H24", "F26"]

func _invasione_attiva() -> bool:
	return int(m.s["anno"]) >= 1943 and m.attiva("USA") and not m.s["pot"]["GB"]["arresa"]

## fattori navali che mancano in un porto per imbarcare le truppe che vi si trovano (negativo = eccesso)
func _deficit_navale(porto: String, escludi := "") -> int:
	var truppe := 0
	var navi := 0
	for x in m.unita_in(porto):
		if x == escludi:
			continue
		var u: Dictionary = m.s["u"][x]
		if not (m.comandante(u["n"]) in ["GB", "USA"]):
			continue
		if u["t"] == "flo":
			navi += m.forza(x)
		elif Motore._terrestre(u["t"]):
			truppe += m.forza(x)
	return truppe + 2 - navi

func _muovi_flotta(uid: String) -> Dictionary:
	var u: Dictionary = m.s["u"][uid]
	if not (m.comandante(u["n"]) in ["GB", "USA"]):
		return {}
	var qui: String = u["h"]
	var rr := m.raggiungibili(uid)
	var dalla_patria: bool = qui == "USA" or D.esagoni[qui]["n"] == "GB"
	if not dalla_patria:
		return {}
	if not _invasione_attiva() and qui != "USA":
		return {}
	# resta se qui serve
	if qui in PORTI_INVASIONE and _deficit_navale(qui, uid) >= 0:
		return {}
	# il porto d'invasione con il maggior bisogno di navi
	var migliore := ""
	var massimo := -999
	for id in PORTI_INVASIONE:
		if not rr.has(id) or id == qui:
			continue
		var dn := _deficit_navale(id)
		if dn > massimo:
			massimo = dn
			migliore = id
	if migliore == "" or (qui != "USA" and massimo <= 0):
		return {}
	return {"t": "muovi", "u": uid, "h": migliore}

## Sbarco anglo-americano: dalle navi in porto verso una costa nemica sguarnita, vicina agli obiettivi
func _sbarco(usate: Dictionary, presi: Dictionary) -> Array:
	var piano := []
	if int(m.s["pot"]["GB"]["opz"] == "off") + int(m.s["pot"]["USA"]["opz"] == "off") == 0:
		return piano
	var ost := ostili("alleati")
	var candidati := {}   # esagono -> unità che possono arrivarci
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if not (m.comandante(u["n"]) in ["GB", "USA"]) or not Motore._terrestre(u["t"]) or usate.has(uid) or not m.puo_muovere(uid):
			continue
		if not D.porti.has(u["h"]):
			continue
		var rr := m.raggiungibili(uid)
		for id in rr:
			if int(rr[id]) != -1 or not ost.has(m.controllo(id)):
				continue
			if not (D.esagoni[id]["n"] in ["FRA", "BEL", "NED", "ITA", "GER", "NOR", "DAN", "GRE", "LIB", "TUN", "ALG", "MAR"]):
				continue
			if not candidati.has(id):
				candidati[id] = []
			candidati[id].append(uid)
	var migliore := ""
	var mv := -999.0
	var obs := obiettivi("alleati")
	for id in candidati:
		var difesa := _minaccia(id, "alleati", ost)
		# forza disponibile per lo sbarco su questo tratto di costa
		var forza := 0
		var tratto := [id]
		for v in D.esagoni[id]["terra"]:
			if candidati.has(v):
				tratto.append(v)
		var unita_tratto := {}
		for t in tratto:
			for x in candidati[t]:
				unita_tratto[x] = true
		for x in unita_tratto:
			forza += m.forza(x)
		if float(forza) < difesa * 0.8 + 3.0 or unita_tratto.size() < 3:
			continue
		var v := _importanza(id) * 1.5 - difesa * 0.4 + float(mini(unita_tratto.size(), 6)) * 1.5
		if D.porti.has(id):
			v += 5.0
		var vicino := 99
		for o in obs:
			var f := campo(o, "alleati")
			if f.has(id):
				vicino = mini(vicino, int(f[id]))
		v -= float(mini(vicino, 30)) * 0.4
		if v > mv:
			mv = v
			migliore = id
	if migliore == "":
		return piano
	# fino a 6 unità: 2 nell'esagono scelto e 2 per ciascuno dei due esagoni costieri accanto
	var tratto := [migliore]
	for v in D.esagoni[migliore]["terra"]:
		if candidati.has(v) and tratto.size() < 3:
			tratto.append(v)
	var usati := {}
	var fflotte := {}   # porto -> fattori navali ancora liberi
	for t in tratto:
		var lista: Array = candidati[t].duplicate()
		lista.sort_custom(func(a, b): return _priorita(a) > _priorita(b))
		var n := 0
		for uid in lista:
			if n >= 2 or usati.has(uid):
				continue
			var porto: String = m.s["u"][uid]["h"]
			if not fflotte.has(porto):
				fflotte[porto] = m._flotte_disponibili(porto, m.comandante(m.s["u"][uid]["n"]))
			if int(fflotte[porto]) < m.forza(uid):
				continue
			fflotte[porto] = int(fflotte[porto]) - m.forza(uid)
			usati[uid] = true
			piano.append({"t": "muovi", "u": uid, "h": t})
			presi[t] = int(presi.get(t, 0)) + 1
			n += 1
	return piano

# -------------------------------------------------------------------------------------
# Strategia: fronti, minacce e obiettivi
# -------------------------------------------------------------------------------------

var _ostili_chiave := ""
var _ostili := {}

## nazioni ostili allo schieramento l: quelle in guerra e, come minaccia futura, la grande potenza
## avversaria ancora neutrale (l'URSS per l'Asse dal 1941, la Germania per l'URSS)
func ostili(l: String) -> Dictionary:
	var chiave := "%s|%d" % [l, int(m.s["prog"])]
	if chiave == _ostili_chiave:
		return _ostili
	var out := {}
	var codici := {}
	for id in m.s["ctrl"]:
		codici[m.s["ctrl"][id]] = true
	for uid in m.s["u"]:
		codici[m.s["u"][uid]["n"]] = true
	for c in codici:
		var lc := m.lato(c)
		if lc == "" or lc == l:
			continue
		var peso := 0.0
		for p in m.potenze_del_lato(l):
			if m.in_guerra(p, c):
				peso = 1.0
		if peso == 0.0 and c in ["URSS", "GER"] and not m.s["pot"]["URSS"]["arresa"]:
			# minaccia potenziale fra Germania e URSS
			var anno := int(m.s["anno"])
			if l == "asse" and c == "URSS":
				peso = 0.0 if anno < 1941 else (0.6 if anno == 1941 else 1.0)
			elif l == "alleati" and c == "GER":
				peso = 0.0 if anno < 1941 else 0.8
		if peso > 0.0:
			out[c] = peso
	_ostili = out
	_ostili_chiave = chiave
	return out

## minaccia su un esagono: fattori terrestri ostili entro 2 esagoni (pesati)
func _minaccia(id: String, l: String, ost: Dictionary) -> float:
	var tot := 0.0
	var visti := {id: 0}
	var coda := [id]
	var i := 0
	while i < coda.size():
		var a: String = coda[i]
		i += 1
		if int(visti[a]) >= 2:
			continue
		for b in D.esagoni[a]["terra"]:
			if visti.has(b):
				continue
			visti[b] = int(visti[a]) + 1
			coda.append(b)
			for x in m.terrestri_in(b):
				var n: String = m.s["u"][x]["n"]
				var c := n if ost.has(n) else m.comandante(n)
				if ost.has(n):
					tot += m.forza(x) * float(ost[n])
				elif ost.has(c) and m.lato(n) != l:
					tot += m.forza(x) * float(ost[c])
	return tot

## esagoni di confine dello schieramento l con il fabbisogno di unità
func fronte_settori(l: String) -> Array:
	var ost := ostili(l)
	var out := []
	for id in m.s["ctrl"]:
		var c: String = m.s["ctrl"][id]
		if m.lato(c) != l or not D.terra(id):
			continue
		if not (m.maggiore(c) or m.s["min"].get(c, {}).get("st", "") in ["alleato", "attaccato"]):
			continue
		var confine := false
		for v in D.esagoni[id]["terra"]:
			var cv := m.controllo(v)
			if ost.has(cv):
				confine = true
			for x in m.terrestri_in(v):
				if ost.has(m.s["u"][x]["n"]) or ost.has(m.comandante(m.s["u"][x]["n"])) and m.lato(m.s["u"][x]["n"]) != l:
					confine = true
		if not confine:
			continue
		var mn := _minaccia(id, l, ost)
		if mn <= 0.0:
			continue
		# minacce trascurabili (un paio di fattori di un paese minore) non tengono ferme le truppe
		if mn < 2.5 and _importanza(id) < 6.0:
			continue
		var bisogno := 1
		if mn >= 9.0 or _importanza(id) >= 6.0:
			bisogno = 2
		# chi è all'offensiva tiene solo uno schermo leggero: le forze servono per lo sfondamento
		if m.opzione(c) == "off" and not str(D.esagoni[id]["tipo"]).contains("C"):
			bisogno = 1
		var prio := mn + _importanza(id) * 1.5 + (2.0 if D.esagoni[id]["t"] != 0 else 0.0)
		out.append({"h": id, "b": bisogno, "p": prio})
	out.sort_custom(func(a, b): return float(a["p"]) > float(b["p"]))
	return out

## sposta unità dalle retrovie (o da settori in eccesso) verso i settori scoperti
func _copri_fronte(l: String, presi: Dictionary, difesa: Dictionary, usate: Dictionary) -> Array:
	var piano := []
	var settori := fronte_settori(l)
	var bisogno := {}
	for st in settori:
		bisogno[st["h"]] = int(st["b"])
	# disponibili: unità terrestri che non servono dove sono
	var disp := []
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) != l or not Motore._terrestre(u["t"]) or not m.puo_muovere(uid) or u["h"] == "USA":
			continue
		disp.append(uid)
	var rr_cache := {}
	var limite := 0
	for st in settori:
		var h: String = st["h"]
		var manca: int = int(st["b"]) - int(difesa.get(h, 0))
		while manca > 0 and limite < 400:
			limite += 1
			var migliore := ""
			var md := 999
			for uid in disp:
				if usate.has(uid):
					continue
				var qui: String = m.s["u"][uid]["h"]
				# non sguarnire un settore che a sua volta ne ha bisogno
				if int(difesa.get(qui, 0)) <= int(bisogno.get(qui, 0)):
					continue
				if not rr_cache.has(uid):
					rr_cache[uid] = m.raggiungibili(uid)
				var rr: Dictionary = rr_cache[uid]
				# per tenere la linea si usa la fanteria: i corazzati servono per attaccare
				var costo := int(rr.get(h, -1)) + (6 if m.s["u"][uid]["t"] == "cor" else 0) + (2 if m.s["u"][uid]["t"] == "par" else 0)
				if rr.has(h) and int(rr[h]) >= 0 and costo < md and int(presi.get(h, 0)) + m.terrestri_in(h).size() < 2:
					md = costo
					migliore = uid
			if migliore == "":
				break
			usate[migliore] = true
			var da: String = m.s["u"][migliore]["h"]
			piano.append({"t": "muovi", "u": migliore, "h": h})
			presi[h] = int(presi.get(h, 0)) + 1
			difesa[da] = int(difesa.get(da, 1)) - 1
			difesa[h] = int(difesa.get(h, 0)) + 1
			manca -= 1
	return piano

var _campi := {}
var _campi_chiave := ""

## obiettivi offensivi dello schieramento: capitali e città obiettivo nemiche
func obiettivi(l: String) -> Dictionary:
	var ost := ostili(l)
	var out := {}
	for id in D.obiettivi + D.capitali.values():
		if id == "" or not D.esagoni.has(id):
			continue
		var c := m.controllo(id)
		if not ost.has(c):
			continue
		# contro i nemici solo potenziali si punta solo quando la Germania prepara Barbarossa
		if float(ost[c]) < 1.0 and not (l == "asse" and _prepara_barbarossa()):
			var in_guerra := false
			for p in m.potenze_del_lato(l):
				if m.in_guerra(p, c):
					in_guerra = true
			if not in_guerra:
				continue
		var tipo: String = D.esagoni[id]["tipo"]
		var peso := 2.0
		if tipo.contains("C"):
			peso = 4.0 if m.maggiore(D.esagoni[id]["n"]) else 3.0
		if tipo.contains("I"):
			peso += 1.0
		out[id] = peso * _peso_strategico(l, id, c)
	return out

## priorità strategiche, come le giocano i giocatori esperti:
## Asse: prima la Francia (Parigi), poi i Balcani prima di Barbarossa, poi Leningrado-Mosca-Ucraina;
## l'Italia punta all'Egitto e a Suez. Alleati: l'URSS contrattacca dal 1943, gli anglo-americani tornano
## sul continente dal 1943 e puntano alla Germania.
func _peso_strategico(l: String, id: String, c: String) -> float:
	var nome: String = D.esagoni[id]["citta"]
	var orig: String = D.esagoni[id]["n"]
	if l == "asse":
		if orig == "FRA" and not m.s["pot"]["FRA"]["arresa"]:
			return 3.0 if nome == "Paris" else 1.8
		if orig in ["BEL", "NED", "LUX"]:
			return 1.5
		if orig in ["DAN", "NOR"]:
			return 0.5
		if orig in ["JUG", "GRE"]:
			return 1.8
		if orig == "URSS":
			return 2.0 if nome in ["Moscow", "Leningrad", "Kiev", "Kharkov"] else 1.5
		if orig in ["EGI", "PAL", "IRQ"] or nome in ["Alexandria", "Suez", "Malta", "Gibraltar"]:
			return 2.0
		if orig == "GB":
			return 0.5
		return 1.0
	# Alleati
	var anno := int(m.s["anno"])
	if orig == "GER":
		return 2.0 if nome == "Berlin" else 1.3
	if orig in ["ITA", "LIB"] and anno >= 1942:
		return 1.6
	if orig in ["FRA", "BEL", "NED"] and anno >= 1943:
		return 1.6
	return 1.0

## distanze via terra da un obiettivo, attraverso territorio amico, nemico o ostile (non neutrale)
func campo(obiettivo: String, l: String) -> Dictionary:
	var chiave := "%s|%d|%s" % [l, int(m.s["turno"]), m.s["fase"]]
	if chiave != _campi_chiave:
		_campi = {}
		_campi_chiave = chiave
	if _campi.has(obiettivo):
		return _campi[obiettivo]
	var ost := ostili(l)
	var dist := {obiettivo: 0}
	var coda := [obiettivo]
	var i := 0
	while i < coda.size():
		var a: String = coda[i]
		i += 1
		for b in D.esagoni[a]["terra"]:
			if dist.has(b) or not D.terra(b):
				continue
			var c := m.controllo(b)
			if c != "" and m.lato(c) != l and not ost.has(c):
				continue
			dist[b] = int(dist[a]) + 1
			coda.append(b)
	_campi[obiettivo] = dist
	return dist

func _a_contatto(id: String, n: String) -> bool:
	for v in D.esagoni[id]["terra"]:
		for x in m.terrestri_in(v):
			if m.in_guerra(n, m.s["u"][x]["n"]) or m.in_guerra(m.comandante(n), m.s["u"][x]["n"]):
				return true
	return false

func _cambio_in_linea(l: String, presi: Dictionary, difesa: Dictionary, usate: Dictionary) -> Array:
	var piano := []
	var deboli := []
	var forti := []
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) != l or not Motore._terrestre(u["t"]) or u["h"] == "USA" or usate.has(uid) or not m.puo_muovere(uid):
			continue
		if m.opzione(u["n"]) != "off":
			continue
		var contatto := _a_contatto(u["h"], u["n"])
		if contatto and m.forza(uid) <= 2 and u["t"] != "cor":
			deboli.append(uid)
		elif not contatto and m.forza(uid) >= 3:
			forti.append(uid)
	forti.sort_custom(func(a, b): return _priorita(a) > _priorita(b))
	var rr_cache := {}
	for w in deboli:
		var h: String = m.s["u"][w]["h"]
		# un'unità forte che può arrivare in quell'esagono
		var scelto := ""
		for f in forti:
			if usate.has(f):
				continue
			if not rr_cache.has(f):
				rr_cache[f] = m.raggiungibili(f)
			if rr_cache[f].has(h) and int(rr_cache[f][h]) >= 0:
				scelto = f
				break
		if scelto == "":
			continue
		# dove arretra la debole: un esagono amico vicino, non a contatto
		var rw := m.raggiungibili(w)
		var dietro := ""
		var bd := 99
		for id in rw:
			if int(rw[id]) < 0 or _a_contatto(id, m.s["u"][w]["n"]) or m.lato(m.controllo(id)) != l:
				continue
			if int(presi.get(id, 0)) + m.terrestri_in(id).size() >= 2:
				continue
			if int(rw[id]) < bd:
				bd = int(rw[id])
				dietro = id
		if dietro == "":
			continue
		usate[w] = true
		usate[scelto] = true
		piano.append({"t": "muovi", "u": w, "h": dietro})
		piano.append({"t": "muovi", "u": scelto, "h": h})
		presi[dietro] = int(presi.get(dietro, 0)) + 1
		var da: String = m.s["u"][scelto]["h"]
		difesa[da] = int(difesa.get(da, 1)) - 1
	return piano

## i tratti più deboli della linea nemica: lì si concentra lo sfondamento (Schwerpunkt)
func punti_deboli(l: String) -> Dictionary:
	var out := {}
	var off := false
	for p in m.potenze_del_lato(l):
		if m.s["pot"][p]["opz"] == "off":
			off = true
	if not off:
		return out
	var cand := []
	var visti := {}
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) != l or not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		for v in D.esagoni[u["h"]]["terra"]:
			if visti.has(v):
				continue
			visti[v] = true
			var dif := m.terrestri_in(v)
			if dif.is_empty():
				continue
			var nem := false
			var fd := 0
			for x in dif:
				if m.in_guerra(u["n"], m.s["u"][x]["n"]) or m.in_guerra(m.comandante(u["n"]), m.s["u"][x]["n"]):
					nem = true
				fd += m.forza(x)
			if not nem:
				continue
			if D.esagoni[v]["t"] != 0:
				fd *= 2
			cand.append([v, float(fd) - _importanza(v) * 0.3])
	cand.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	for c in cand.slice(0, 4):
		out[c[0]] = 3.5
	return out

## ogni unità punta all'obiettivo più conveniente del suo teatro, con un po' di bilanciamento
func _assegna_obiettivi(l: String, unita: Array, usate: Dictionary) -> Dictionary:
	var obs := obiettivi(l)
	for k in punti_deboli(l):
		obs[k] = maxf(float(obs.get(k, 0.0)), 3.5)
	var out := {}
	if obs.is_empty():
		return out
	var carico := {}
	for uid in unita:
		if usate.has(uid):
			continue
		var u: Dictionary = m.s["u"][uid]
		if not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		var migliore := ""
		var mv := 99999.0
		for o in obs:
			var f := campo(o, l)
			if not f.has(u["h"]):
				continue
			var pen := float(carico.get(o, 0)) * 0.3
			# obiettivo sguarnito: basta un'unità
			if int(carico.get(o, 0)) > 0 and m.terrestri_in(o).is_empty() and _forza_nemica_vicina(o, u["n"], 2) == 0:
				pen += 12.0
			var v := float(f[u["h"]]) - float(obs[o]) * 3.0 + pen
			if v < mv:
				mv = v
				migliore = o
		if migliore != "":
			out[uid] = migliore
			carico[migliore] = int(carico.get(migliore, 0)) + m.forza(uid)
	return out

func _presidi(piano: Array, difesa: Dictionary, fronte: Dictionary, l: String, usate := {}) -> Array:
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
			if m.lato(u["n"]) != l or not Motore._terrestre(u["t"]) or not m.puo_muovere(uid) or usate.has(uid):
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

func _muovi_terrestre(uid: String, fronte: Dictionary, presi: Dictionary, difesa: Dictionary, sfruttamento: bool, obiettivo := "") -> Dictionary:
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
	var f_ob: Dictionary = campo(obiettivo, m.s["lato"]) if obiettivo != "" else {}
	var best_v := _valore_posizione(qui, n, off, fronte, difesa, true, uid) - _peso_ob(f_ob, qui)
	for id in rr:
		if int(presi.get(id, 0)) + m.terrestri_in(id).size() >= 2:
			continue
		var v := _valore_posizione(id, n, off, fronte, difesa, false, uid) - _peso_ob(f_ob, id)
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

## attrazione verso l'obiettivo assegnato: ogni esagono di avvicinamento conta
func _peso_ob(f: Dictionary, id: String) -> float:
	if f.is_empty():
		return 0.0
	return float(f.get(id, 80)) * 1.3

## l'esagono è protetto da un fiume verso tutti i vicini ostili
func _dietro_fiume(id: String, n: String) -> bool:
	var ost := ostili(m.lato(n))
	var trovati := 0
	for v in D.esagoni[id]["terra"]:
		if ost.has(m.controllo(v)):
			trovati += 1
			if not D.fiume_tra(id, v):
				return false
	return trovati > 0

func _vicino_a_amici(id: String, n: String) -> bool:
	for v in D.esagoni[id]["vicini"]:
		for x in m.terrestri_in(v):
			if m.lato(m.s["u"][x]["n"]) == m.lato(n):
				return true
	return false

func _valore_posizione(id: String, n: String, off: bool, fronte: Dictionary, difesa: Dictionary, resto: bool, uid: String) -> float:
	var d := int(fronte.get(id, 60))
	var v := -float(mini(d, 12)) * 0.6
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
				v += 1.5
			elif _dietro_fiume(id, n):
				v += 1.2
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
	# Blitzkrieg: nel 1939-41 la Germania accetta il 2-1 anche contro pile forti
	var blitz: bool = l == "asse" and int(m.s["anno"]) <= 1941
	if int(v["base"]) >= 6 and imp < 6.0 and not blitz:
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
			riserva = 80 if int(m.s["anno"]) == 1941 else 50
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
			# la Germania costruisce aviazione presto: serve a raggiungere le colonne buone
			if p == "GER" and int(m.s["anno"]) <= 1941 and budget >= 30:
				return 6.0
			return 2.0 if budget >= 60 else -1.0
		"flo":
			return 0.5 if budget >= 80 and p in ["GB", "USA"] else -1.0
	return 0.0 - c * 0.01

## distanze via terra dagli esagoni controllati da certe nazioni
func _distanza_da(codici: Array) -> Dictionary:
	var dist := {}
	var coda := []
	for id in m.s["ctrl"]:
		if codici.has(m.s["ctrl"][id]):
			dist[id] = 0
			coda.append(id)
	var i := 0
	while i < coda.size():
		var a: String = coda[i]
		i += 1
		for b in D.esagoni[a]["terra"]:
			if not D.terra(b) or dist.has(b):
				continue
			dist[b] = int(dist[a]) + 1
			coda.append(b)
	return dist

## Riequilibrio fra i teatri della Germania: le forze tedesche si dividono fra ovest ed est
## in proporzione alla minaccia (anche quella sovietica prima della guerra, dal 1941).
## Restituisce i ridispiegamenti da fare e aggiorna occ.
func _riequilibrio_tedesco(occ: Dictionary, quanti: int) -> Array:
	var piano := []
	if quanti <= 0 or not m.attiva("GER") or m.s["pot"]["URSS"]["arresa"]:
		return piano
	var ost := ostili("asse")
	if not ost.has("URSS"):
		return piano
	var occidentali := []
	for c in ["FRA", "GB", "USA"]:
		if ost.has(c):
			occidentali.append(c)
	var d_est := _distanza_da(["URSS"])
	var d_ovest := _distanza_da(occidentali) if occidentali.size() > 0 else {}
	var d_mio := _distanza_da(["GER", "ITA"])
	var dem_est := 0.0
	var dem_ovest := 0.0
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		if int(d_mio.get(u["h"], 99)) > 4:
			# forze anglo-americane in patria: possibile sbarco, pesano la metà
			if occidentali.has(m.comandante(u["n"])) and D.esagoni[u["h"]]["n"] == "GB":
				dem_ovest += m.forza(uid) * 0.5
			continue
		if u["n"] == "URSS":
			dem_est += m.forza(uid) * float(ost["URSS"])
		elif occidentali.has(m.comandante(u["n"])):
			dem_ovest += m.forza(uid)
	if dem_est <= 0.0:
		return piano
	var f_est := 0
	var f_ovest := 0
	var occ_ovest := []
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if u["n"] != "GER" or not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		var de := int(d_est.get(u["h"], 99))
		var dw := int(d_ovest.get(u["h"], 99))
		if de <= dw:
			f_est += m.forza(uid)
		else:
			f_ovest += m.forza(uid)
			if dw >= 2:
				occ_ovest.append(uid)
	if _prepara_barbarossa():
		dem_est *= 1.6
	var obiettivo_est := float(f_est + f_ovest) * dem_est / maxf(1.0, dem_est + dem_ovest * 1.2)
	if float(f_est) >= obiettivo_est * 0.9:
		return piano
	# prima le unità più lontane dal nemico occidentale
	occ_ovest.sort_custom(func(a, b): return int(d_ovest.get(m.s["u"][a]["h"], 99)) > int(d_ovest.get(m.s["u"][b]["h"], 99)))
	var mancano := obiettivo_est - float(f_est)
	for uid in occ_ovest:
		if quanti <= 0 or mancano <= 0:
			break
		var best := ""
		var bv := 999
		for id in m.destinazioni_sr(uid):
			if int(occ.get(id, 0)) >= 2:
				continue
			var de := int(d_est.get(id, 99))
			if de < 1 or de > 3:
				continue
			var v := de * 3 + (0 if D.esagoni[id]["citta"] != "" else 1) + int(occ.get(id, 0))
			if v < bv:
				bv = v
				best = id
		if best == "":
			continue
		piano.append({"t": "sr", "u": uid, "h": best})
		occ[best] = int(occ.get(best, 0)) + 1
		occ[m.s["u"][uid]["h"]] = int(occ.get(m.s["u"][uid]["h"], 1)) - 1
		mancano -= m.forza(uid)
		quanti -= 1
	return piano

func _piano_sr() -> Array:
	var piano := []
	var l: String = m.s["lato"]
	var fronte := _distanza_fronte(l)
	var settori := fronte_settori(l)
	var obs := obiettivi(l)
	var occ := {}
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) == l and Motore._terrestre(u["t"]):
			occ[u["h"]] = int(occ.get(u["h"], 0)) + 1
	var bisogno := {}
	for st in settori:
		bisogno[st["h"]] = int(st["b"])
	var usati_sr := {}
	if l == "alleati" and (_invasione_attiva() or (int(m.s["anno"]) == 1942 and m.attiva("USA"))):
		for p in ["USA", "GB"]:
			var n_sr := m.sr_rimasti(p)
			var cand := []
			for uid in m.s["u"]:
				var u: Dictionary = m.s["u"][uid]
				if u["n"] != p or not Motore._terrestre(u["t"]) or u["h"] in PORTI_INVASIONE:
					continue
				if u["h"] == "USA" or (D.esagoni.has(u["h"]) and D.esagoni[u["h"]]["n"] == "GB"):
					cand.append(uid)
			cand.sort_custom(func(a, b): return _priorita(a) > _priorita(b))
			for uid in cand:
				if n_sr <= 0:
					break
				var dest := m.destinazioni_sr(uid)
				for id in PORTI_INVASIONE:
					if dest.has(id) and int(occ.get(id, 0)) < 2:
						piano.append({"t": "sr", "u": uid, "h": id})
						occ[id] = int(occ.get(id, 0)) + 1
						usati_sr[uid] = true
						n_sr -= 1
						break
	if l == "asse":
		for d in _riequilibrio_tedesco(occ, m.sr_rimasti("GER")):
			piano.append(d)
			usati_sr[d["u"]] = true
	# forza verso ciascun obiettivo già presente nei dintorni (per mandare rinforzi dove servono)
	for p in m.potenze_del_lato(l):
		var n_sr := m.sr_rimasti(p)
		for x in usati_sr:
			if m.comandante(m.s["u"][x]["n"]) == p:
				n_sr -= 1
		if n_sr <= 0:
			continue
		var cand := []
		for uid in m.s["u"]:
			var u: Dictionary = m.s["u"][uid]
			if m.comandante(u["n"]) != p or not m.maggiore(u["n"]) or not Motore._terrestre(u["t"]) or usati_sr.has(uid):
				continue
			var qui: String = u["h"]
			if qui != "USA" and int(occ.get(qui, 0)) <= int(bisogno.get(qui, 0)):
				continue
			var d := int(fronte.get(qui, 99)) if qui != "USA" else 99
			if d >= 2:
				cand.append(uid)
		# prima le unità più lontane dal fronte (le retrovie si svuotano verso il combattimento)
		cand.sort_custom(func(a, b): return int(fronte.get(m.s["u"][a]["h"], 99)) * 10 + _priorita(a) > int(fronte.get(m.s["u"][b]["h"], 99)) * 10 + _priorita(b))
		for uid in cand:
			if n_sr <= 0:
				break
			var dest := m.destinazioni_sr(uid)
			if dest.is_empty():
				continue
			var u: Dictionary = m.s["u"][uid]
			var d0 := int(fronte.get(u["h"], 99)) if u["h"] != "USA" else 99
			var best := ""
			var bv := -9999.0
			for id in dest:
				if int(occ.get(id, 0)) >= 2:
					continue
				var d := int(fronte.get(id, 99))
				var manca0 := int(bisogno.get(id, 0)) - int(occ.get(id, 0))
				if d >= d0 and manca0 <= 0:
					continue
				var v := -float(d) * 1.5
				# settore scoperto: priorità massima
				var manca := int(bisogno.get(id, 0)) - int(occ.get(id, 0))
				if manca > 0:
					v += 12.0 + manca * 4.0
				# vicinanza al miglior obiettivo
				var mo := 999
				for o in obs:
					var f := campo(o, l)
					if f.has(id):
						mo = mini(mo, int(f[id]) - int(obs[o]) * 2)
				if mo < 999:
					v -= float(mo) * 0.8
				if d == 0:
					v -= 20.0
				if v > bv:
					bv = v
					best = id
			if best != "":
				piano.append({"t": "sr", "u": uid, "h": best})
				occ[best] = int(occ.get(best, 0)) + 1
				occ[u["h"]] = int(occ.get(u["h"], 1)) - 1
				n_sr -= 1
	return piano
