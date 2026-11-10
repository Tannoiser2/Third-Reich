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
				# Barbarossa parte solo con una forza adeguata (mai d'inverno); se nel 1941 non si è pronti,
				# si attacca nella primavera 1942 con tutto ciò che c'è, prima che l'URSS entri in guerra
				var invernale: bool = st == 3
				var pronta: bool = m.s["pot"]["FRA"]["arresa"] and _pronti_a_est() and not invernale
				if t >= 1941 * 4 + 1 and brp >= 35 + 15 and (pronta or t >= 1942 * 4 + 0):
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
				# Stalin non attacca per primo: aspetta l'estate 1942 (quando la guerra scoppia comunque)
				if t >= 1942 * 4 + 1:
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
		# conta chi può raggiungere il confine e attaccare nel primo turno di guerra
		# contano solo le truppe tedesche: gli alleati minori fanno da complemento
		var portata := 5 if u["t"] == "cor" else 4
		if u["n"] == "GER" and int(d_est.get(u["h"], 99)) <= portata:
			asse += m.forza(uid)
		elif u["n"] == "URSS" and int(d_asse.get(u["h"], 99)) <= 4:
			sov += m.forza(uid)
	# in autunno si accetta un rapporto un po' più basso pur di non attaccare in inverno
	var rapporto := 0.55 if int(m.s["stag"]) >= 2 else 0.65
	return asse >= 40 and float(asse) >= float(sov) * rapporto

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
	return a >= 1940 and not m.s["pot"]["GER"]["guerra"].has("URSS") and m.s["pot"]["FRA"]["arresa"]

## la Blitzkrieg a est dura finché i tedeschi non sono in netta inferiorità sul fronte russo
## e comunque non oltre la fine del 1942
func _blitz_in_corso() -> bool:
	if int(m.s["anno"]) > 1942:
		return false
	var ge := 0
	var so := 0
	var d_est := _distanza_da(["URSS"])
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		if u["n"] == "URSS":
			so += m.forza(uid)
		elif m.lato(u["n"]) == "asse" and int(d_est.get(u["h"], 99)) <= 4:
			ge += m.forza(uid)
	return float(ge) >= float(so) * 0.55

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
	_navi_previste = {}
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
		for x in _guarnigioni_capitali(l):
			usate[x] = true
	if l == "alleati":
		for x in _presidio_egitto():
			usate[x] = true
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
	# 4. schieramento d'attacco: le unità si raggruppano attorno ai bersagli scelti per attaccarli
	#    a 3-1 nella fase di combattimento (invece di avanzare sparpagliate verso obiettivi lontani)
	if not sfruttamento:
		for dec in _prepara_attacchi(l, presi, difesa, usate):
			piano.append(dec)
	if not sfruttamento and l == "asse":
		for x in _guarnigioni_vallo():
			usate[x] = true
		for dec in _copri_vallo(presi, difesa, usate):
			piano.append(dec)
	if not sfruttamento and l == "alleati" and _invasione_attiva():
		for dec in _sbarco(usate, presi):
			piano.append(dec)
			usate[dec["u"]] = true
		# le truppe nei porti d'imbarco restano pronte per l'ondata successiva
		for p in PORTI_INVASIONE:
			for x in m.terrestri_in(p):
				if m.comandante(m.s["u"][x]["n"]) in ["GB", "USA"]:
					usate[x] = true
	if sfruttamento:
		for dec in _piano_sfruttamento(l, presi, usate):
			piano.append(dec)
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

## Sfruttamento: i corazzati che hanno sfondato puntano in profondità verso un bersaglio debole
## da attaccare subito nel combattimento di sfruttamento, possibilmente in coppia
func _piano_sfruttamento(l: String, presi: Dictionary, usate: Dictionary) -> Array:
	var piano := []
	var gruppi := {}
	for uid in m.s["sfrutt"]:
		if not m.s["u"].has(uid) or not m.puo_muovere(uid, true) or usate.has(uid):
			continue
		var h: String = m.s["u"][uid]["h"]
		if not gruppi.has(h):
			gruppi[h] = []
		gruppi[h].append(uid)
	var fronte := _distanza_fronte(l)
	for h in gruppi:
		var g: Array = gruppi[h]
		var fa := 0
		for uid in g:
			fa += m.forza(uid)
		var rr := m.raggiungibili(g[0], true)
		for uid in g.slice(1):
			var r2 := m.raggiungibili(uid, true)
			for k in rr.keys():
				if not r2.has(k):
					rr.erase(k)
		var migliore := ""
		var mv := -999.0
		for v in rr:
			if int(rr[v]) < 0:
				continue
			if m.terrestri_in(v).size() + int(presi.get(v, 0)) + g.size() > 2 and v != h:
				continue
			for b in D.esagoni[v]["terra"]:
				var dif := m.terrestri_in(b)
				if dif.is_empty() or m.s["attaccate"].has(b) or m.lato(m.s["u"][dif[0]]["n"]) == l:
					continue
				var fd := 0
				for x in dif:
					fd += m.forza(x)
				if int(D.esagoni[b]["t"]) in [1, 2]:
					fd *= 2
				var rapporto := float(fa) / maxf(1.0, float(fd))
				if rapporto < 2.0:
					continue
				var val := (30.0 if rapporto >= 3.0 else 15.0) + _importanza(b) * 2.0 + float(rr[v]) * 0.5
				# in profondità: lontano dalla nostra linea di partenza è meglio (accerchiamenti)
				val += float(mini(int(fronte.get(v, 0)), 4)) * -1.0
				if val > mv:
					mv = val
					migliore = v
		if migliore == "":
			# nessun bersaglio a portata: puntata in profondità alle spalle del nemico (accerchiamento)
			var d_mio := _distanza_da(m.potenze_del_lato(l))
			for v in rr:
				if int(rr[v]) < 0 or v == h:
					continue
				if m.terrestri_in(v).size() + int(presi.get(v, 0)) + g.size() > 2:
					continue
				var prof := float(mini(int(d_mio.get(v, 0)), 6))
				var nemici := 0.0
				var pericolo := 0.0
				for w in D.esagoni[v]["terra"]:
					for x in m.terrestri_in(w):
						if m.lato(m.s["u"][x]["n"]) != l:
							pericolo += float(m.forza(x))
					for z in D.esagoni[w]["terra"]:
						for x in m.terrestri_in(z):
							if m.lato(m.s["u"][x]["n"]) != l:
								nemici += 1.0
				# non da soli contro forze superiori
				if pericolo > float(fa) * 1.5:
					continue
				var val := prof * 3.0 + nemici * 1.2 + _importanza(v) * 1.5
				if val > mv:
					mv = val
					migliore = v
		if migliore == "" or migliore == h:
			continue
		for uid in g:
			usate[uid] = true
			piano.append({"t": "muovi", "u": uid, "h": migliore})
			presi[migliore] = int(presi.get(migliore, 0)) + 1
	return piano

## Raggruppa le unità attorno ai difensori nemici più convenienti, finché ogni attacco scelto
## ha almeno 3 contro 1 (o 2 contro 1 se il bersaglio è importante). Vale per chi ha scelto l'offensiva.
func _prepara_attacchi(l: String, presi: Dictionary, difesa: Dictionary, usate: Dictionary) -> Array:
	var piano := []
	var off := false
	for p in m.potenze_del_lato(l):
		if m.s["pot"][p]["opz"] == "off" and m.attiva(p):
			off = true
	if not off:
		return piano
	# unità disponibili e loro portata
	var disp := []
	var rr := {}
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) != l or not Motore._terrestre(u["t"]) or usate.has(uid) or not m.puo_muovere(uid) or u["h"] == "USA":
			continue
		if m.s["pot"].has(m.comandante(u["n"])) and m.s["pot"][m.comandante(u["n"])]["opz"] != "off":
			continue
		# chi tiene da solo un esagono del fronte non lo lascia
		if int(difesa.get(u["h"], 0)) <= 1 and _a_contatto(u["h"], u["n"]) and _importanza(u["h"]) >= 6.0:
			continue
		disp.append(uid)
	if disp.is_empty():
		return piano
	# bersagli: esagoni con unità nemiche vicino alle nostre forze
	var bersagli := []
	var visti := {}
	for uid in disp:
		var u: Dictionary = m.s["u"][uid]
		var vicini := {u["h"]: true}
		for v in D.esagoni[u["h"]]["terra"]:
			vicini[v] = true
			for w in D.esagoni[v]["terra"]:
				vicini[w] = true
				for z in D.esagoni[w]["terra"]:
					vicini[z] = true
		for b in vicini:
			if visti.has(b):
				continue
			visti[b] = true
			var dif := m.terrestri_in(b)
			if dif.is_empty():
				continue
			var nemico := false
			for x in dif:
				var n: String = m.s["u"][x]["n"]
				if m.lato(n) != l and m.lato(n) != "" and (m.in_guerra(m.comandante(u["n"]), n) or m.in_guerra(m.comandante(u["n"]), m.comandante(n))):
					nemico = true
			if not nemico:
				continue
			var fd := 0
			for x in dif:
				fd += m.forza(x)
			var molt := 2 if int(D.esagoni[b]["t"]) in [1, 2] else 1
			var imp := _importanza(b)
			bersagli.append({"h": b, "dif": fd * molt, "imp": imp})
	if bersagli.is_empty():
		return piano
	# prima i bersagli deboli e importanti
	bersagli.sort_custom(func(a, b): return float(a["dif"]) - float(a["imp"]) * 0.8 < float(b["dif"]) - float(b["imp"]) * 0.8)
	var usati := {}
	var n_att := 0
	for bs in bersagli:
		if n_att >= 20:
			break
		var b: String = bs["h"]
		# 2-1 con un piccolo margine: con la tabella dei combattimenti è già un buon rischio
		var serve: float = float(bs["dif"]) * 2.0 + 1.0
		# forza già a contatto (non spostata)
		var forza := 0.0
		for v in D.esagoni[b]["terra"]:
			for x in m.terrestri_in(v):
				if m.lato(m.s["u"][x]["n"]) == l and not usati.has(x) and (usate.has(x) or not disp.has(x)):
					forza += float(m.forza(x))
		var mosse := []
		var occ_loc := {}
		# candidati: unità che possono raggiungere un esagono adiacente al bersaglio
		var cand := []
		for uid in disp:
			if usati.has(uid):
				continue
			if not rr.has(uid):
				rr[uid] = m.raggiungibili(uid)
			var dist_u: Dictionary = rr[uid]
			var qui: String = m.s["u"][uid]["h"]
			var migliore := ""
			var md := 999
			if b in D.esagoni[qui]["terra"]:
				migliore = qui
				md = 0
			else:
				for v in D.esagoni[b]["terra"]:
					if not dist_u.has(v) or int(dist_u[v]) < 0:
						continue
					var occ: int = m.terrestri_in(v).size() + int(presi.get(v, 0)) + int(occ_loc.get(v, 0))
					if occ >= 2:
						continue
					if int(dist_u[v]) < md:
						md = int(dist_u[v])
						migliore = v
			if migliore != "":
				cand.append([uid, migliore, md])
		cand.sort_custom(func(a, b): return float(m.forza(a[0])) * 2.0 - float(a[2]) > float(m.forza(b[0])) * 2.0 - float(b[2]))
		for c in cand:
			if forza >= serve:
				break
			var uid: String = c[0]
			var v: String = c[1]
			if v != m.s["u"][uid]["h"]:
				var occ: int = m.terrestri_in(v).size() + int(presi.get(v, 0)) + int(occ_loc.get(v, 0))
				if occ >= 2:
					continue
				occ_loc[v] = int(occ_loc.get(v, 0)) + 1
			mosse.append([uid, v])
			forza += float(m.forza(uid))
		if forza < serve:
			continue
		for mv in mosse:
			var uid: String = mv[0]
			var v: String = mv[1]
			usati[uid] = true
			usate[uid] = true
			if v == m.s["u"][uid]["h"]:
				continue
			piano.append({"t": "muovi", "u": uid, "h": v})
			presi[v] = int(presi.get(v, 0)) + 1
			difesa[m.s["u"][uid]["h"]] = int(difesa.get(m.s["u"][uid]["h"], 1)) - 1
			difesa[v] = int(difesa.get(v, 0)) + 1
		n_att += 1
	return piano

## porti britannici da cui partono gli sbarchi sulla Manica
const PORTI_INVASIONE := ["L22", "K21", "K24", "H24", "F26", "AA7", "GG19"]
## teatro mediterraneo
const AFRICA := ["LIB", "EGI"]
const PORTI_EGITTO := ["LL28", "LL31", "MM30"]
const PORTI_LIBIA := ["II17", "KK21", "KK24"]
const PORTI_ITALIA_SUD := ["Z23", "AA24", "DD21"]

## forza terrestre in Libia ed Egitto: {"asse": n, "alleati": n, "ger": n, "gb_unita": n}
## la strada costiera del deserto, da Tripoli a Suez
const CATENA_AFRICA := ["II17", "KK18", "MM20", "KK21", "KK24", "LL26", "LL28", "MM29", "MM30"]

## obiettivo comune per tutte le unità di uno schieramento nel deserto: si avanza lungo la costa
## se si è nettamente più forti, altrimenti si tiene il caposaldo costiero più avanzato
func obiettivo_deserto(l: String) -> String:
	var fa := _forze_africa()
	var mie := float(fa[l])
	var loro := float(fa["alleati" if l == "asse" else "asse"])
	if mie <= 0.0:
		return ""
	var catena: Array = CATENA_AFRICA.duplicate()
	if l == "alleati":
		catena.reverse()   # gli Alleati avanzano verso ovest
	# il primo caposaldo non nostro lungo la direzione di marcia
	var ultimo_mio := ""
	var primo_nemico := ""
	for id in catena:
		if m.lato(m.controllo(id)) == l:
			ultimo_mio = id
		elif primo_nemico == "":
			primo_nemico = id
			break
	if primo_nemico != "" and (mie >= loro * 1.4 + 2.0 or loro <= 0.0):
		return primo_nemico
	return ultimo_mio if ultimo_mio != "" else primo_nemico

func _forze_africa() -> Dictionary:
	var out := {"asse": 0, "alleati": 0, "ger": 0, "gb_unita": 0, "ita": 0}
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		var h: String = u["h"]
		if h == "USA" or not Motore._terrestre(u["t"]) or not (D.esagoni[h]["n"] in AFRICA):
			continue
		var l := m.lato(u["n"])
		if l == "":
			continue
		out[l] = int(out[l]) + m.forza(uid)
		if u["n"] == "GER":
			out["ger"] = int(out["ger"]) + 1
		if u["n"] == "ITA":
			out["ita"] = int(out["ita"]) + m.forza(uid)
		if u["n"] == "GB" and D.esagoni[h]["n"] == "EGI":
			out["gb_unita"] = int(out["gb_unita"]) + 1
	return out

func _italia_contro_gb() -> bool:
	return m.attiva("ITA") and m.in_guerra("ITA", "GB")

## unità britanniche che restano a presidio dell'Egitto (non vengono ritirate né ridispiegate altrove)
## capitale minacciata: riserve ridispiegate a difesa della capitale e dei suoi dintorni
func _sr_difesa_capitali(l: String, occ: Dictionary, usati: Dictionary) -> Array:
	var piano := []
	for p in m.potenze_del_lato(l):
		if not m.maggiore(p) or m.s["pot"][p]["arresa"] or p == "FRA":
			continue
		var cap: String = D.capitali.get(p, "")
		if cap == "" or m.controllo(cap) != p:
			continue
		var minaccia := _forza_nemica_vicina(cap, p, 5)
		if minaccia <= 0:
			continue
		# forze amiche già vicine alla capitale
		var mie := 0
		var vicini := [cap]
		for v in D.esagoni[cap]["terra"]:
			vicini.append(v)
		for v in vicini:
			for x in m.terrestri_in(v):
				if m.lato(m.s["u"][x]["n"]) == l:
					mie += m.forza(x)
		var n_sr := m.sr_rimasti(p)
		for x in usati:
			if m.comandante(m.s["u"][x]["n"]) == p:
				n_sr -= 1
		if mie >= minaccia or n_sr <= 0:
			continue
		var d_cap := {}
		var cand := []
		for uid in m.s["u"]:
			var u: Dictionary = m.s["u"][uid]
			if u["n"] != p or not Motore._terrestre(u["t"]) or usati.has(uid) or u["h"] == "USA" or u["h"] in vicini:
				continue
			cand.append(uid)
		cand.sort_custom(func(a, b): return m.forza(a) > m.forza(b))
		for uid in cand:
			if n_sr <= 0 or mie >= minaccia:
				break
			var dest := m.destinazioni_sr(uid)
			for v in vicini:
				if dest.has(v) and int(occ.get(v, 0)) < 2:
					piano.append({"t": "sr", "u": uid, "h": v})
					occ[v] = int(occ.get(v, 0)) + 1
					occ[m.s["u"][uid]["h"]] = int(occ.get(m.s["u"][uid]["h"], 1)) - 1
					usati[uid] = true
					mie += m.forza(uid)
					n_sr -= 1
					break
	return piano

## ogni capitale tiene sempre almeno un'unità: non la si sposta né la si ridispiega
func _guarnigioni_capitali(l: String) -> Dictionary:
	var out := {}
	for p in m.potenze_del_lato(l):
		# la Francia difende Parigi con la manovra, non con una guarnigione fissa
		if not m.maggiore(p) or m.s["pot"][p]["arresa"] or p == "FRA":
			continue
		var cap: String = D.capitali.get(p, "")
		if cap == "" or m.controllo(cap) != p:
			continue
		var scelta := ""
		for x in m.terrestri_in(cap):
			if m.lato(m.s["u"][x]["n"]) != l:
				continue
			if scelta == "" or m.forza(x) < m.forza(scelta) or m.s["u"][scelta]["t"] == "cor":
				scelta = x
		if scelta != "":
			out[scelta] = true
		# con il nemico vicino la capitale tiene una pila intera
		if _forza_nemica_vicina(cap, p, 6) > 0:
			for x in m.terrestri_in(cap):
				if m.lato(m.s["u"][x]["n"]) == l:
					out[x] = true
	return out

func _presidio_egitto() -> Dictionary:
	var out := {}
	if m.s["pot"]["ITA"]["arresa"]:
		return out
	var gb := []
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if u["n"] == "GB" and Motore._terrestre(u["t"]) and u["h"] != "USA" and D.esagoni[u["h"]]["n"] == "EGI":
			gb.append(uid)
	var minimo := 3 if _italia_contro_gb() else 2
	if gb.size() <= minimo:
		for uid in gb:
			out[uid] = true
	# anche le guarnigioni coloniali francesi restano dove sono
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if u["n"] == "FRA" and u["h"] != "USA" and D.esagoni[u["h"]]["n"] in ["TUN", "ALG", "MAR", "LIS"]:
			out[uid] = true
	return out

## ridispiegamenti mediterranei: rinforzi britannici in Egitto, Afrika Korps e rinforzi italiani in Libia
func _sr_mediterraneo(occ: Dictionary, usati: Dictionary) -> Array:
	var piano := []
	var l: String = m.s["lato"]
	if m.s["pot"]["ITA"]["arresa"]:
		return piano
	var fa := _forze_africa()
	if l == "alleati" and not m.s["pot"]["GB"]["arresa"]:
		var obiettivo := 4
		if _italia_contro_gb():
			obiettivo = maxi(8, int(float(fa["asse"]) * 1.3) + 3)
			# dal 1942 l'ottava armata passa all'offensiva: serve il doppio delle forze dell'Asse
			if int(m.s["anno"]) >= 1942:
				obiettivo = maxi(12, int(float(fa["asse"]) * 2.0) + 2)
		var mancano := obiettivo - int(fa["alleati"])
		var max_sr := mini(2 if int(m.s["anno"]) <= 1940 else 3, m.sr_rimasti("GB"))
		if mancano <= 0 or max_sr <= 0:
			return piano
		var cand := []
		for uid in m.s["u"]:
			var u: Dictionary = m.s["u"][uid]
			if u["n"] != "GB" or not Motore._terrestre(u["t"]) or usati.has(uid) or u["h"] == "USA":
				continue
			if D.esagoni[u["h"]]["n"] in AFRICA or u["h"] in ["AA7", "GG19"]:
				continue
			# Londra resta difesa
			if u["h"] == "K23" and int(occ.get("K23", 0)) <= 1:
				continue
			cand.append(uid)
		cand.sort_custom(func(a, b): return _priorita(a) > _priorita(b))
		for uid in cand:
			if max_sr <= 0 or mancano <= 0:
				break
			var dest := m.destinazioni_sr(uid)
			for id in PORTI_EGITTO:
				if dest.has(id) and int(occ.get(id, 0)) < 2:
					piano.append({"t": "sr", "u": uid, "h": id})
					occ[id] = int(occ.get(id, 0)) + 1
					occ[m.s["u"][uid]["h"]] = int(occ.get(m.s["u"][uid]["h"], 1)) - 1
					usati[uid] = true
					max_sr -= 1
					mancano -= m.forza(uid)
					break
		return piano
	if l != "asse" or not _italia_contro_gb():
		return piano
	# Italia: tiene in Libia una forza almeno pari a quella britannica in Egitto
	var porti_lib := []
	for id in PORTI_LIBIA:
		if m.lato(m.controllo(id)) == "asse":
			porti_lib.append(id)
	# l'Afrika Korps parte solo a Barbarossa iniziata (prima ogni corazzato serve a est)
	var per_potenza := {"ITA": 2, "GER": 2 if m.s["pot"]["GER"]["guerra"].has("URSS") and m.s["pot"]["FRA"]["arresa"] and int(fa["ger"]) < 3 else 0}
	if int(fa["ita"]) >= maxi(8, int(fa["alleati"]) + 2):
		per_potenza["ITA"] = 0
	# finché la Francia combatte l'Italia rinforza la Libia solo se è in inferiorità
	if not m.s["pot"]["FRA"]["arresa"] and int(fa["ita"]) >= int(fa["alleati"]):
		per_potenza["ITA"] = 0
	for p in ["GER", "ITA"]:
		var n_sr := mini(int(per_potenza[p]), m.sr_rimasti(p))
		if n_sr <= 0:
			continue
		var cand := []
		for uid in m.s["u"]:
			var u: Dictionary = m.s["u"][uid]
			if u["n"] != p or not Motore._terrestre(u["t"]) or usati.has(uid) or u["h"] == "USA" or u["t"] == "rim":
				continue
			if D.esagoni[u["h"]]["n"] in AFRICA:
				continue
			# la Germania manda i corazzati, l'Italia ciò che ha in patria
			if p == "GER" and not (u["t"] in ["cor", "fan"]):
				continue
			if p == "ITA" and D.esagoni[u["h"]]["n"] != "ITA":
				continue
			cand.append(uid)
		# prima chi è già in un porto del sud Italia
		cand.sort_custom(func(a, b): return int(m.s["u"][a]["h"] in PORTI_ITALIA_SUD) * 100 + _priorita(a) > int(m.s["u"][b]["h"] in PORTI_ITALIA_SUD) * 100 + _priorita(b))
		for uid in cand:
			if n_sr <= 0:
				break
			var dest := m.destinazioni_sr(uid)
			var scelto := ""
			for id in porti_lib:
				if dest.has(id) and int(occ.get(id, 0)) < 2:
					scelto = id
					break
			if scelto == "" and p == "GER":
				# prima tappa: un porto dell'Italia meridionale
				for id in PORTI_ITALIA_SUD:
					if dest.has(id) and int(occ.get(id, 0)) < 2:
						scelto = id
						break
			if scelto == "":
				continue
			piano.append({"t": "sr", "u": uid, "h": scelto})
			occ[scelto] = int(occ.get(scelto, 0)) + 1
			occ[m.s["u"][uid]["h"]] = int(occ.get(m.s["u"][uid]["h"], 1)) - 1
			usati[uid] = true
			n_sr -= 1
	return piano

func _invasione_attiva() -> bool:
	if m.s["pot"]["GB"]["arresa"]:
		return false
	var a := int(m.s["anno"])
	if a >= 1943 and m.attiva("USA"):
		return true
	# secondo fronte: dal 1942 (o già nel 1941, a Barbarossa iniziata) se la Francia è caduta
	return m.s["pot"]["FRA"]["arresa"] and m.s["pot"]["GER"]["guerra"].has("URSS") and (a >= 1942 or (a == 1941 and int(m.s["stag"]) >= 2))

## esigenza di forza per uno sbarco: prima del 1943 solo contro coste poco difese
func _margine_sbarco() -> Array:
	if int(m.s["anno"]) >= 1943:
		return [0.8, 3.0]
	return [1.5, 4.0]

## Vallo Atlantico: esagoni chiave della costa occidentale che la Germania presidia dopo la caduta
## della Francia, in proporzione alle forze anglo-americane pronte in Gran Bretagna
var _vallo_lista: Array = []
func vallo_atlantico() -> Array:
	if _vallo_lista.is_empty():
		var tmp := []
		for id in D.esagoni:
			var e: Dictionary = D.esagoni[id]
			if not e["costa"] or not (e["n"] in ["FRA", "BEL", "NED"]):
				continue
			if not D.porti.has(id) and e["citta"] == "":
				continue
			var d := D.distanza(id, "L22")
			if d > 14:
				continue
			tmp.append([d, id])
		tmp.sort()
		for x in tmp:
			_vallo_lista.append(x[1])
	return _vallo_lista

func _presidi_vallo_richiesti() -> int:
	if not m.s["pot"]["FRA"]["arresa"] or m.s["pot"]["GB"]["arresa"]:
		return 0
	var f := 0
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if not Motore._terrestre(u["t"]) or not (m.comandante(u["n"]) in ["GB", "USA"]):
			continue
		if u["h"] == "USA" or D.esagoni[u["h"]]["n"] == "GB":
			f += m.forza(uid)
	return clampi(int(round(float(f) / 7.0)), 2, 9)

## unità dell'Asse già al loro posto sul Vallo (una per esagono richiesto): non vanno spostate
func _guarnigioni_vallo() -> Dictionary:
	var out := {}
	var n := _presidi_vallo_richiesti()
	var lista := vallo_atlantico()
	for i in mini(n, lista.size()):
		var id: String = lista[i]
		if m.lato(m.controllo(id)) != "asse":
			continue
		var migliore := ""
		for x in m.terrestri_in(id):
			if m.lato(m.s["u"][x]["n"]) == "asse" and (migliore == "" or m.s["u"][x]["t"] != "cor"):
				migliore = x
		if migliore != "":
			out[migliore] = id
	return out

## manda fanteria agli esagoni del Vallo ancora scoperti
func _copri_vallo(presi: Dictionary, difesa: Dictionary, usate: Dictionary) -> Array:
	var piano := []
	var n := _presidi_vallo_richiesti()
	if n <= 0:
		return piano
	var lista := vallo_atlantico()
	var fronte := _distanza_fronte("asse")
	var d_est := _distanza_da(["URSS"])
	for i in mini(n, lista.size()):
		var id: String = lista[i]
		if m.lato(m.controllo(id)) != "asse" or int(difesa.get(id, 0)) + int(presi.get(id, 0)) > 0:
			continue
		var migliore := ""
		var md := 999.0
		for uid in m.s["u"]:
			var u: Dictionary = m.s["u"][uid]
			if m.lato(u["n"]) != "asse" or not Motore._terrestre(u["t"]) or usate.has(uid) or not m.puo_muovere(uid) or u["h"] == "USA":
				continue
			if u["t"] == "cor" or u["t"] == "par":
				continue
			# non si tolgono truppe dal fronte russo
			if int(d_est.get(u["h"], 99)) <= 2 and m.s["pot"]["GER"]["guerra"].has("URSS"):
				continue
			if int(fronte.get(u["h"], 99)) <= 1 and int(difesa.get(u["h"], 0)) <= 1:
				continue
			var rr := m.raggiungibili(uid)
			if not rr.has(id) or int(rr[id]) < 0:
				continue
			var c := float(rr[id]) + (0.0 if u["t"] == "fan" else 2.0)
			if c < md:
				md = c
				migliore = uid
		if migliore != "":
			usate[migliore] = true
			piano.append({"t": "muovi", "u": migliore, "h": id})
			presi[id] = int(presi.get(id, 0)) + 1
			difesa[m.s["u"][migliore]["h"]] = int(difesa.get(m.s["u"][migliore]["h"], 1)) - 1
			difesa[id] = int(difesa.get(id, 0)) + 1
	return piano

## fattori navali che mancano in un porto per imbarcare le truppe di una nazione (negativo = eccesso)
var _navi_previste := {}   # "porto|naz" -> variazione di fattori navali prevista in questo turno
func _deficit_navale(porto: String, naz: String, escludi := "") -> int:
	var truppe := 0
	var navi: int = int(_navi_previste.get(porto + "|" + naz, 0))
	for x in m.unita_in(porto):
		if x == escludi:
			continue
		var u: Dictionary = m.s["u"][x]
		if m.comandante(u["n"]) != naz:
			continue
		if u["t"] == "flo":
			navi += m.forza(x)
		elif Motore._terrestre(u["t"]):
			truppe += m.forza(x)
	return truppe + 2 - navi

func _muovi_flotta(uid: String) -> Dictionary:
	var u: Dictionary = m.s["u"][uid]
	var naz := m.comandante(u["n"])
	if not (naz in ["GB", "USA"]):
		return {}
	var qui: String = u["h"]
	var rr := m.raggiungibili(uid)
	var dalla_patria: bool = qui == "USA" or D.esagoni[qui]["n"] == "GB" or qui in PORTI_INVASIONE
	if not dalla_patria:
		return {}
	if not _invasione_attiva() and qui != "USA" and int(m.s["anno"]) < 1942:
		return {}
	# resta se qui serve
	if qui in PORTI_INVASIONE and _deficit_navale(qui, naz, uid) >= 0:
		return {}
	# il porto d'invasione dove le truppe della stessa nazione hanno più bisogno di navi
	var migliore := ""
	var massimo := -999
	for id in PORTI_INVASIONE:
		if not rr.has(id) or id == qui:
			continue
		var dn := _deficit_navale(id, naz)
		if dn > massimo:
			massimo = dn
			migliore = id
	if migliore == "" or (qui != "USA" and massimo <= 0):
		return {}
	_navi_previste[migliore + "|" + naz] = int(_navi_previste.get(migliore + "|" + naz, 0)) + m.forza(uid)
	_navi_previste[qui + "|" + naz] = int(_navi_previste.get(qui + "|" + naz, 0)) - m.forza(uid)
	return {"t": "muovi", "u": uid, "h": migliore}

var debug_sbarco := false
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
			if not (D.esagoni[id]["n"] in ["FRA", "BEL", "NED", "ITA", "NOR", "GRE", "LIB", "TUN", "ALG", "MAR"]):
				# sbarcare direttamente in Germania o in Danimarca solo a guerra ormai decisa
				if not (D.esagoni[id]["n"] in ["GER", "DAN"] and int(m.s["anno"]) >= 1944):
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
		var mg := _margine_sbarco()
		var minimo := 3
		if difesa <= 2.0 and (D.porti.has(id) or D.esagoni[id]["citta"] != "" or _importanza(id) >= 4.0):
			minimo = 2
		if float(forza) < difesa * float(mg[0]) + float(mg[1]) or unita_tratto.size() < minimo:
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
				# caduta la Francia, la Germania comincia subito a guardare a est
				if anno == 1940 and m.s["pot"]["FRA"]["arresa"]:
					peso = 0.4
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
	# Blitzkrieg a est: nelle prime fasi di Barbarossa la Germania non stende un cordone difensivo
	# lungo tutto il confine sovietico, ma concentra le forze dove attacca
	var blitz_est: bool = l == "asse" and m.s["pot"]["GER"]["guerra"].has("URSS") and m.opzione("GER") == "off" and _blitz_in_corso()
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
		if blitz_est and _importanza(id) < 6.0:
			var sovietico := false
			for v in D.esagoni[id]["terra"]:
				if m.controllo(v) == "URSS":
					sovietico = true
					break
			if sovietico:
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
	# nel deserto tutti seguono la strada costiera verso lo stesso caposaldo
	var ob_des := obiettivo_deserto(l) if not m.s["pot"]["ITA"]["arresa"] else ""
	if ob_des != "":
		for uid in unita:
			var u: Dictionary = m.s["u"][uid]
			if usate.has(uid) or not Motore._terrestre(u["t"]) or u["h"] == "USA":
				continue
			if D.esagoni[u["h"]]["n"] in AFRICA:
				out[uid] = ob_des
	if obs.is_empty():
		return out
	var carico := {}
	for uid in unita:
		if usate.has(uid) or out.has(uid):
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
		# le città dell'interno non immobilizzano truppe: si presidiano solo quelle vicine al fronte
		var limite := 2
		if str(D.esagoni[id]["tipo"]).contains("C"):
			limite = 99
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
			if not amica and not (m.lato(n) == "alleati" and _invasione_attiva() and _vicino_a_amici(id, n)):
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
	var d_est := {}
	if l == "asse" and (_prepara_barbarossa() or m.s["pot"]["GER"]["guerra"].has("URSS")) and not m.s["pot"]["URSS"]["arresa"]:
		d_est = _distanza_da(["URSS"])
	for p in m.costruttori():
		var brp := int(m.s["pot"][p]["brp"])
		var riserva := 15
		if p == "GER" and int(m.s["anno"]) <= 1941 and not m.s["pot"]["GER"]["guerra"].has("URSS"):
			# nel 1941 si tengono i BRP per dichiarare Barbarossa (35) e l'offensiva (15);
			# d'inverno, rimandata Barbarossa alla primavera, si spende tutto (in primavera arrivano i BRP nuovi)
			riserva = 50
			if int(m.s["anno"]) == 1941 and int(m.s["stag"]) == 3:
				riserva = 15
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
				# la Germania schiera le nuove unità verso la Russia
				if p == "GER" and not d_est.is_empty() and Motore._terrestre(e[0]):
					d = int(d_est.get(id, 50))
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
			# per la Germania l'aviazione è la chiave dello sfondamento: viene prima dei corazzati
			if p == "GER" and budget >= 30:
				return 9.5
			if p == "ITA" and budget >= 40:
				return 5.0
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
func _riequilibrio_tedesco(occ: Dictionary, quanti: int, bloccati := {}) -> Array:
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
				dem_ovest += m.forza(uid) * (0.2 if m.s["pot"]["FRA"]["arresa"] else 0.5)
			continue
		if u["n"] == "URSS":
			dem_est += m.forza(uid) * float(ost["URSS"])
		elif occidentali.has(m.comandante(u["n"])) and not (D.esagoni[u["h"]]["n"] in AFRICA + ["PAL", "TUN", "ALG", "MAR", "LIS", "IRQ", "PER", "TUR", "SPA"]):
			dem_ovest += m.forza(uid)
	if dem_est <= 0.0:
		return piano
	# con gli americani in guerra serve sempre una riserva a ovest (circa un terzo dell'esercito)
	if m.attiva("USA") and not m.s["pot"]["GB"]["arresa"]:
		dem_ovest = maxf(dem_ovest, dem_est * 0.4)
	var f_est := 0
	var f_ovest := 0
	var occ_ovest := []
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if u["n"] != "GER" or not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		var de := int(d_est.get(u["h"], 99))
		var dw := int(d_ovest.get(u["h"], 99))
		# conta a est solo chi è davvero vicino al fronte russo: le riserve in Germania vanno portate avanti
		if de <= 3:
			f_est += m.forza(uid)
		else:
			if dw > de or dw >= 99:
				pass
			f_ovest += m.forza(uid)
			if (dw >= 2 or de < dw) and not bloccati.has(uid):
				occ_ovest.append(uid)
	if _prepara_barbarossa():
		dem_est *= 1.6
	var obiettivo_est := float(f_est + f_ovest) * dem_est / maxf(1.0, dem_est + dem_ovest * 1.2)
	if float(f_est) >= obiettivo_est * 0.9:
		return piano
	# prima i corazzati, poi le unità più lontane dal nemico occidentale
	occ_ovest.sort_custom(func(a, b): return _priorita(a) * 10.0 + float(d_ovest.get(m.s["u"][a]["h"], 99)) > _priorita(b) * 10.0 + float(d_ovest.get(m.s["u"][b]["h"], 99)))
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
	var bloccati := _presidio_egitto()
	for x in _guarnigioni_capitali(l):
		bloccati[x] = true
	for x in bloccati:
		usati_sr[x] = true
	for d in _sr_difesa_capitali(l, occ, usati_sr):
		piano.append(d)
	for d in _sr_mediterraneo(occ, usati_sr):
		piano.append(d)
	for x in bloccati:
		usati_sr.erase(x)
	if l == "alleati" and (_invasione_attiva() or (int(m.s["anno"]) == 1942 and m.attiva("USA"))):
		for p in ["USA", "GB"]:
			var n_sr := m.sr_rimasti(p)
			for x in usati_sr:
				if m.comandante(m.s["u"][x]["n"]) == p:
					n_sr -= 1
			var cand := []
			for uid in m.s["u"]:
				var u: Dictionary = m.s["u"][uid]
				if u["n"] != p or not Motore._terrestre(u["t"]) or u["h"] in PORTI_INVASIONE:
					continue
				if u["h"] == "USA" or (D.esagoni.has(u["h"]) and D.esagoni[u["h"]]["n"] == "GB"):
					cand.append(uid)
			cand.sort_custom(func(a, b): return _priorita(a) > _priorita(b))
			var porti := PORTI_INVASIONE.duplicate()
			porti.sort_custom(func(a, b): return _deficit_navale(a, p) < _deficit_navale(b, p))
			for uid in cand:
				if n_sr <= 0:
					break
				var dest := m.destinazioni_sr(uid)
				for id in porti:
					if dest.has(id) and int(occ.get(id, 0)) < 2:
						piano.append({"t": "sr", "u": uid, "h": id})
						occ[id] = int(occ.get(id, 0)) + 1
						usati_sr[uid] = true
						n_sr -= 1
						break
	if l == "asse":
		for x in _guarnigioni_vallo():
			bloccati[x] = true
		var n_vallo := mini(1 if _prepara_barbarossa() else 2, m.sr_rimasti("GER"))
		var lista_v := vallo_atlantico()
		for i in mini(_presidi_vallo_richiesti(), lista_v.size()):
			var id: String = lista_v[i]
			if n_vallo <= 0:
				break
			if m.lato(m.controllo(id)) != "asse" or int(occ.get(id, 0)) > 0:
				continue
			for uid in m.s["u"]:
				var u: Dictionary = m.s["u"][uid]
				if u["n"] != "GER" or u["t"] != "fan" or usati_sr.has(uid) or bloccati.has(uid) or u["h"] == "USA":
					continue
				if D.esagoni[u["h"]]["n"] != "GER" or int(fronte.get(u["h"], 99)) <= 1:
					continue
				if m.destinazioni_sr(uid).has(id):
					piano.append({"t": "sr", "u": uid, "h": id})
					occ[id] = 1
					occ[u["h"]] = int(occ.get(u["h"], 1)) - 1
					usati_sr[uid] = true
					n_vallo -= 1
					break
		var gia := 0
		var escl := bloccati.duplicate()
		for x in usati_sr:
			escl[x] = true
			if m.comandante(m.s["u"][x]["n"]) == "GER":
				gia += 1
		for d in _riequilibrio_tedesco(occ, m.sr_rimasti("GER") - gia, escl):
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
			if m.comandante(u["n"]) != p or not m.maggiore(u["n"]) or not Motore._terrestre(u["t"]) or usati_sr.has(uid) or bloccati.has(uid):
				continue
			if l == "alleati" and _invasione_attiva() and u["h"] in PORTI_INVASIONE:
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
