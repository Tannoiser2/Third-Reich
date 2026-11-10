## Motore delle regole: stato della partita, sequenza di gioco e risoluzione.
## Logica pura e deterministica (dadi da un generatore nello stato): la stessa sequenza di decisioni
## produce la stessa partita su ogni dispositivo, così il gioco online scambia solo le decisioni.
##
## Il gioco chiede una decisione alla volta (richiesta()) e la applica (applica()).
## Versioni: "base" (Rise and Decline of the Third Reich) e "advanced" (Advanced Third Reich):
## stessa mappa a esagoni e stesse regole di fondo; l'Advanced aggiunge diplomazia, inverno russo,
## petrolio, guerra strategica e aiuti affitti e prestiti.
class_name Motore
extends RefCounted

signal evento(testo: String)

var D: Dati
var s := {}

const FASI := ["dichiarazioni", "opzioni", "movimento", "combattimento", "sfruttamento", "costruzione", "ridispiegamento"]
const NOMI_FASE := {"diplomazia": "Diplomazia", "dichiarazioni": "Dichiarazioni di guerra", "opzioni": "Scelta delle opzioni",
	"movimento": "Movimento", "combattimento": "Combattimento", "avanzata": "Avanzata dopo il combattimento",
	"sfruttamento": "Sfruttamento dello sfondamento", "costruzione": "Costruzione", "ridispiegamento": "Ridispiegamento strategico", "fine": "Fine della partita"}
const NOMI_OPZIONE := {"off": "Offensiva", "log": "Logoramento", "pas": "Passo"}

func _init(dati: Dati = null) -> void:
	if dati == null:
		dati = Dati.new()
		dati.carica()
	D = dati

# =====================================================================================
# Nuova partita
# =====================================================================================

## modo: "base" o "advanced"; seme: numero per i dadi
func nuova(modo: String, seme: int) -> void:
	s = {"modo": modo, "anno": 1939, "stag": 2, "turno": 1, "fase": "dichiarazioni", "lato": "asse", "meta": 0,
		"prima": "asse", "rng": seme % 2147483647, "pot": {}, "ctrl": {}, "u": {}, "pool": {}, "min": {},
		"sfond": [], "sfrutt": [], "avanzata": {}, "attaccate": [], "log": [], "fine": "", "prog": 0, "nid": 1,
		"dp": {}, "sr_usati": {}, "ultimo": {}, "fine_anno": 1945, "fine_stag": 1}
	for p in Dati.MAGGIORI:
		s["pot"][p] = {"base": Dati.BRP_BASE[p], "brp": Dati.BRP_BASE[p], "guerra": [], "opz": "", "arresa": false}
	s["pot"]["USA"]["brp"] = 0
	for code in Dati.MINORI:
		s["min"][code] = {"st": "neutrale", "lato": "", "di": "", "nemici": []}
	s["min"]["VIC"] = {"st": "inesistente", "lato": "", "di": "", "nemici": []}
	# controllo iniziale
	for id in D.esagoni:
		var h: Dictionary = D.esagoni[id]
		if h["t"] == 9 or h["n"] == "":
			continue
		var n: String = h["n"]
		s["ctrl"][id] = Dati.COLONIE.get(n, n)
	# forze
	for n in D.forze:
		s["pool"][n] = []
		if Dati.MAGGIORI.has(n):
			for e in D.forze[n]["pool"]:
				s["pool"][n].append(e)
	# Situazione dell'autunno 1939: la Germania ha invaso la Polonia; Francia e Gran Bretagna le hanno dichiarato guerra.
	_guerra("GER", "POL")
	_guerra("GER", "GB")
	_guerra("GER", "FRA")
	_schiera_iniziale()
	_attiva_minore("POL", "alleati", "GER")
	_log("Autunno 1939: la Germania ha invaso la Polonia. Francia e Gran Bretagna sono in guerra con la Germania.")
	_log("Versione %s del regolamento." % ("Advanced" if modo == "advanced" else "base"))
	_inizio_turno_giocatore()

# =====================================================================================
# Utilità
# =====================================================================================

func _dado() -> int:
	s["rng"] = (int(s["rng"]) * 48271) % 2147483647
	return 1 + int(s["rng"]) % 6

func _log(t: String) -> void:
	s["log"].append(t)
	if s["log"].size() > 150:
		s["log"] = s["log"].slice(s["log"].size() - 120)
	evento.emit(t)

func advanced() -> bool:
	return s.get("modo", "base") == "advanced"

func data_testo() -> String:
	return "%s %d" % [Dati.STAGIONI[int(s["stag"])], int(s["anno"])]

func finita() -> bool:
	return s.get("fine", "") != ""

## lato di una nazione ("asse", "alleati" o "" se neutrale)
func lato(n: String) -> String:
	if Dati.LATO_DI.has(n):
		return Dati.LATO_DI[n]
	if s["min"].has(n):
		return s["min"][n]["lato"]
	return ""

## la potenza che comanda le unità di una nazione
func comandante(n: String) -> String:
	if Dati.LATO_DI.has(n):
		return n
	var l := lato(n)
	return Dati.CAPO.get(l, "")

func maggiore(n: String) -> bool:
	return Dati.LATO_DI.has(n)

## una potenza è attiva quando è in guerra con qualcuno e non si è arresa
func attiva(n: String) -> bool:
	if maggiore(n):
		var p: Dictionary = s["pot"][n]
		return not p["arresa"] and p["guerra"].size() > 0
	if s["min"].has(n):
		return s["min"][n]["st"] in ["attaccato", "alleato"]
	return false

## a e b sono in guerra fra loro?
func in_guerra(a: String, b: String) -> bool:
	if a == b or a == "" or b == "":
		return false
	if maggiore(a) and maggiore(b):
		return s["pot"][a]["guerra"].has(b)
	if not maggiore(a) and maggiore(b):
		return in_guerra(b, a)
	if maggiore(a):
		var m: Dictionary = s["min"].get(b, {})
		if m.is_empty():
			return false
		if m["st"] == "attaccato":
			if m["nemici"].has(a):
				return true
			# un minore aggredito combatte anche chi è in guerra con i suoi protettori? no: solo gli aggressori
			return false
		if m["st"] == "alleato":
			# un minore alleato è in guerra con chi è in guerra con il capofila del suo schieramento
			return in_guerra(a, Dati.CAPO[m["lato"]]) or (s["pot"][a]["guerra"].has(b))
		return s["pot"][a]["guerra"].has(b)
	# due minori: sono nemici se stanno in schieramenti opposti e almeno uno è alleato attivo
	var la := lato(a)
	var lb := lato(b)
	if la == "" or lb == "" or la == lb:
		return false
	var ma: Dictionary = s["min"][a]
	var mb: Dictionary = s["min"][b]
	if ma["st"] == "attaccato":
		for x in ma["nemici"]:
			if comandante(b) == x or in_guerra(x, b):
				return true
		return false
	if mb["st"] == "attaccato":
		return in_guerra(b, a)
	return in_guerra(Dati.CAPO[la], Dati.CAPO[lb])

## la nazione n può stare in un esagono controllato da c (amico o in guerra e in offensiva)?
func amico(n: String, c: String) -> bool:
	if c == n:
		return true
	var ln := lato(n)
	if ln == "" or lato(c) != ln:
		return false
	return attiva(n) and attiva(c)

func unita_in(id: String) -> Array:
	var out := []
	for uid in s["u"]:
		if s["u"][uid]["h"] == id:
			out.append(uid)
	return out

var _cache_occ := {}
var _cache_ver := -1

func _occupazione() -> Dictionary:
	if _cache_ver == int(s["prog"]) and not _cache_occ.is_empty():
		return _cache_occ
	var occ := {}
	for uid in s["u"]:
		var h: String = s["u"][uid]["h"]
		if not occ.has(h):
			occ[h] = []
		occ[h].append(uid)
	_cache_occ = occ
	_cache_ver = int(s["prog"])
	return occ

func _invalida() -> void:
	_cache_occ = {}
	_cache_ver = -1

func terrestri_in(id: String) -> Array:
	var out := []
	for uid in _occupazione().get(id, []):
		if _terrestre(s["u"][uid]["t"]):
			out.append(uid)
	return out

static func _terrestre(t: String) -> bool:
	return t in ["fan", "cor", "par", "rim"]

func nazione_unita(uid: String) -> String:
	return s["u"][uid]["n"]

## l'esagono contiene unità terrestri nemiche della nazione n?
func nemici_in(id: String, n: String) -> bool:
	for uid in terrestri_in(id):
		if in_guerra(n, s["u"][uid]["n"]):
			return true
	return false

## zona di controllo nemica: esagono adiacente a unità terrestri in guerra con n
func zoc(id: String, n: String) -> bool:
	for v in D.esagoni[id]["terra"]:
		if nemici_in(v, n):
			return true
	return false

func controllo(id: String) -> String:
	return s["ctrl"].get(id, "")

func forza(uid: String) -> int:
	return int(s["u"][uid]["a"])

func _nuova_unita(n: String, t: String, a: int, m: int, h: String) -> String:
	var uid := "u%d" % int(s["nid"])
	s["nid"] = int(s["nid"]) + 1
	s["u"][uid] = {"n": n, "t": t, "a": a, "m": m, "h": h, "mv": false, "at": false, "us": false, "nr": 0, "sf": false}
	_invalida()
	return uid

func _elimina(uid: String) -> void:
	var u: Dictionary = s["u"][uid]
	var n: String = u["n"]
	if maggiore(n) and not s["pot"][n]["arresa"]:
		s["pool"][n].append([u["t"], u["a"], u["m"]])
	s["u"].erase(uid)
	s["sfrutt"].erase(uid)
	_invalida()

func descrizione_unita(uid: String) -> String:
	var u: Dictionary = s["u"][uid]
	var n: String = u["n"]
	match u["t"]:
		"avi":
			return "Aviazione %s, %d fattori" % [_agg(n), u["a"]]
		"flo":
			return "Flotta %s, %d fattori" % [_agg(n), u["a"]]
		"rim":
			return "Rimpiazzi %s 1-3" % _agg(n)
	return "%s %s %d-%d" % [Dati.NOMI_TIPO[u["t"]].capitalize(), _agg(n), u["a"], u["m"]]

func _agg(n: String) -> String:
	return Dati.AGGETTIVI.get(n, "(" + Dati.nome(n) + ")")

# =====================================================================================
# Schieramento automatico (inizio partita e paesi minori che entrano in guerra)
# =====================================================================================

## esagoni di confine della nazione n verso la nazione m (in ordine: città, pianura)
func _confine(n: String, verso: Array) -> Array:
	var out := []
	for id in s["ctrl"]:
		if s["ctrl"][id] != n:
			continue
		var ok := false
		for v in D.esagoni[id]["vicini"]:
			if verso.has(controllo(v)):
				ok = true
		if ok:
			out.append(id)
	return out

func _territorio(n: String) -> Array:
	var out := []
	for id in s["ctrl"]:
		if s["ctrl"][id] == n and (D.esagoni[id]["n"] == n or Dati.COLONIE.get(D.esagoni[id]["n"], "") == n):
			out.append(id)
	return out

## distribuisce le unità terrestri di n sugli esagoni indicati (2 per esagono), le altre all'interno
func _schiera(n: String, unita: Array, fronte: Array, interno: Array) -> void:
	var posti := []
	for id in fronte:
		if terrestri_in(id).size() < 2 and D.esagoni[id]["t"] != 9:
			posti.append(id)
	for id in interno:
		if not posti.has(id) and terrestri_in(id).size() < 2:
			posti.append(id)
	var i := 0
	for e in unita:
		var t: String = e[0]
		if not _terrestre(t):
			continue
		var tentativi := 0
		while tentativi < posti.size():
			var id: String = posti[i % posti.size()]
			i += 1
			tentativi += 1
			if terrestri_in(id).size() < 2:
				_nuova_unita(n, t, int(e[1]), int(e[2]), id)
				break

func _schiera_aria_mare(n: String, unita: Array, citta: Array) -> void:
	var porti := []
	var aero := []
	for id in citta:
		if D.porti.has(id):
			porti.append(id)
		aero.append(id)
	if aero.is_empty():
		return
	var ia := 0
	var ip := 0
	for e in unita:
		match e[0]:
			"avi":
				_nuova_unita(n, "avi", int(e[1]), int(e[2]), aero[ia % aero.size()])
				ia += 1
			"flo":
				if porti.size() > 0:
					_nuova_unita(n, "flo", int(e[1]), 0, porti[ip % porti.size()])
					ip += 1

func _citta_di(n: String, includi_colonie := false) -> Array:
	var out := []
	for id in D.esagoni:
		var h: Dictionary = D.esagoni[id]
		if h["citta"] == "" or controllo(id) != n:
			continue
		if h["n"] == n or (includi_colonie and Dati.COLONIE.get(h["n"], "") == n):
			out.append(id)
	return out

func _ordina_citta(lista: Array, prima: Array) -> Array:
	var a := []
	for x in prima:
		if lista.has(x) and not a.has(x):
			a.append(x)
	for x in lista:
		if not a.has(x):
			a.append(x)
	return a

func _id_citta(nome: String) -> String:
	for id in D.esagoni:
		if D.esagoni[id]["citta"] == nome:
			return id
	return ""

func _ids(nomi: Array) -> Array:
	var out := []
	for nm in nomi:
		var id := _id_citta(nm)
		if id != "":
			out.append(id)
	return out

func _schiera_iniziale() -> void:
	var F: Dictionary = D.forze
	# Germania: grosso contro la Polonia, il resto a ovest
	var ger: Array = F["GER"]["inizio"]
	var est := _confine("GER", ["POL"])
	var ovest := _confine("GER", ["FRA", "BEL", "NED", "LUX"])
	var ger_t := []
	for e in ger:
		if _terrestre(e[0]):
			ger_t.append(e)
	_schiera("GER", ger_t.slice(0, 16), est, est)
	_schiera("GER", ger_t.slice(16), ovest, _territorio("GER"))
	_schiera_aria_mare("GER", ger, _ordina_citta(_citta_di("GER"), _ids(["Berlin", "Kiel", "Wilhelmshaven", "Breslau", "Konigsberg"])))
	# Italia: penisola, Libia e Albania
	var ita: Array = F["ITA"]["inizio"]
	var ita_t := []
	for e in ita:
		if _terrestre(e[0]):
			ita_t.append(e)
	_schiera("ITA", ita_t.slice(0, 2), _ids(["Tripoli"]), _territorio("ITA"))
	_schiera("ITA", ita_t.slice(2, 3), _ids(["Tirane"]), _territorio("ITA"))
	_schiera("ITA", ita_t.slice(3), _confine("ITA", ["FRA"]) + _ids(["Rome", "Naples"]), _territorio("ITA"))
	_schiera_aria_mare("ITA", ita, _ordina_citta(_citta_di("ITA"), _ids(["Taranto", "Naples", "Rome", "Spezia", "Messina"])))
	# Francia: confine tedesco, una divisione in Siria e una in Tunisia
	var fra: Array = F["FRA"]["inizio"]
	var fra_t := []
	for e in fra:
		if _terrestre(e[0]):
			fra_t.append(e)
	_schiera("FRA", fra_t.slice(0, 1), _ids(["Damascus"]), _territorio("FRA"))
	_schiera("FRA", fra_t.slice(1, 2), _ids(["Tunis"]), _territorio("FRA"))
	_schiera("FRA", fra_t.slice(2), _confine("FRA", ["GER", "LUX", "BEL"]) + _confine("FRA", ["ITA"]), _territorio("FRA"))
	_schiera_aria_mare("FRA", fra, _ordina_citta(_citta_di("FRA"), _ids(["Paris", "Brest", "Marseilles", "Cherbourg"])))
	# Gran Bretagna: patria, Egitto, Gibilterra, Malta
	var gb: Array = F["GB"]["inizio"]
	var gb_t := []
	for e in gb:
		if _terrestre(e[0]):
			gb_t.append(e)
	_schiera("GB", gb_t.slice(0, 4), _ids(["London", "Portsmouth"]), _territorio("GB"))
	_schiera("GB", gb_t.slice(4, 6), _ids(["Alexandria"]), _ids(["Cairo"]))
	_schiera("GB", gb_t.slice(6, 7), _ids(["Gibraltar"]), _ids(["Gibraltar"]))
	_schiera("GB", gb_t.slice(7), _ids(["Malta"]), _ids(["Malta", "Suez"]))
	_schiera_aria_mare("GB", gb, _ordina_citta(_citta_di("GB", true), _ids(["Scapa Flow", "Portsmouth", "London", "Alexandria", "Gibraltar", "Malta", "Rosyth"])))
	# Unione Sovietica: frontiera occidentale
	var urss: Array = F["URSS"]["inizio"]
	_schiera("URSS", urss, _confine("URSS", ["POL", "BAL", "RUM", "FIN"]), _territorio("URSS"))
	_schiera_aria_mare("URSS", urss, _ordina_citta(_citta_di("URSS"), _ids(["Leningrad", "Sevastopol", "Moscow", "Kiev"])))
	# Stati Uniti: le forze iniziali arrivano con l'entrata in guerra

func _schiera_usa() -> void:
	for e in D.forze["USA"]["inizio"]:
		_nuova_unita("USA", e[0], int(e[1]), int(e[2]), "USA")

## un paese minore entra in guerra: le sue forze si schierano, comandate dallo schieramento "lato"
func _attiva_minore(n: String, lt: String, aggressore: String) -> void:
	var m: Dictionary = s["min"][n]
	if aggressore != "":
		m["st"] = "attaccato"
		if not m["nemici"].has(aggressore):
			m["nemici"].append(aggressore)
	else:
		m["st"] = "alleato"
	m["lato"] = lt
	if s.get("_minori_schierati", {}).has(n):
		return
	if not s.has("_minori_schierati"):
		s["_minori_schierati"] = {}
	s["_minori_schierati"][n] = true
	if not D.forze.has(n):
		return
	var unita: Array = D.forze[n]["inizio"]
	var verso := []
	if aggressore != "":
		verso.append(aggressore)
		for id in _territorio(aggressore):
			pass
	else:
		for x in Dati.MAGGIORI:
			if lato(x) != lt and lato(x) != "":
				verso.append(x)
	var cap: String = D.capitali.get(n, "")
	var fronte := _confine(n, verso)
	var interno := _territorio(n)
	if cap != "":
		interno.push_front(cap)
	_schiera(n, unita, fronte, interno)
	_schiera_aria_mare(n, unita, _ordina_citta(_citta_di(n), [cap]))

# =====================================================================================
# Guerra
# =====================================================================================

func _guerra(a: String, b: String) -> void:
	if maggiore(a):
		if not s["pot"][a]["guerra"].has(b):
			s["pot"][a]["guerra"].append(b)
	if maggiore(b):
		if not s["pot"][b]["guerra"].has(a):
			s["pot"][b]["guerra"].append(a)

## dichiarazioni possibili per la potenza p
func dichiarazioni_possibili(p: String) -> Array:
	var out := []
	var pot: Dictionary = s["pot"][p]
	if pot["arresa"]:
		return out
	var lp := lato(p)
	for q in Dati.MAGGIORI:
		if q == p or lato(q) == lp or pot["guerra"].has(q) or s["pot"][q]["arresa"]:
			continue
		if q == "USA":
			continue
		# l'URSS non può dichiarare guerra alla Germania prima del 1942; nessuno all'URSS prima del 1941 (patto)
		if p == "URSS" and int(s["anno"]) < 1942:
			continue
		if q == "URSS" and int(s["anno"]) < 1941 and p != "GER":
			continue
		if p == "USA" or (q == "URSS" and int(s["anno"]) < 1940):
			continue
		if pot["brp"] >= Dati.COSTO_GUERRA_MAGGIORE:
			out.append(q)
	for m in s["min"]:
		var mm: Dictionary = s["min"][m]
		if mm["st"] == "conquistato" or mm["st"] == "inesistente":
			continue
		if mm["st"] == "alleato" and mm["lato"] == lp:
			continue
		if mm["st"] == "attaccato" and (mm["nemici"].has(p) or mm["lato"] == lp):
			continue
		if mm["st"] == "alleato" and in_guerra(p, m):
			continue
		if m == "VIC" and lp == "asse":
			continue
		if not _confina_o_raggiunge(p, m):
			continue
		if pot["brp"] >= Dati.COSTO_GUERRA_MINORE:
			out.append(m)
	return out

## una potenza può attaccare un paese solo se ha unità o territorio vicino (via terra o via mare)
func _confina_o_raggiunge(p: String, m: String) -> bool:
	for id in s["ctrl"]:
		if s["ctrl"][id] != m:
			continue
		for v in D.esagoni[id]["vicini"]:
			var c := controllo(v)
			if c == p or (c != "" and lato(c) == lato(p) and attiva(c)):
				return true
		if D.esagoni[id]["costa"]:
			return true
	return false

func _dichiara(p: String, c: String) -> void:
	var costo := Dati.COSTO_GUERRA_MAGGIORE if maggiore(c) else Dati.COSTO_GUERRA_MINORE
	s["pot"][p]["brp"] = int(s["pot"][p]["brp"]) - costo
	if maggiore(c):
		_guerra(p, c)
		# chi entra in guerra si trova in guerra anche con gli alleati del bersaglio già in lotta con il proprio schieramento,
		# e gli alleati del dichiarante già in guerra si trovano in guerra con il bersaglio
		for q in Dati.MAGGIORI:
			if lato(q) == lato(c) and q != c and not s["pot"][q]["arresa"]:
				for r in potenze_del_lato(lato(p)):
					if s["pot"][r]["guerra"].has(q):
						_guerra(p, q)
			if lato(q) == lato(p) and q != p and attiva(q) and not s["pot"][q]["arresa"]:
				_guerra(q, c)
		_log("%s dichiara guerra a %s (%d BRP)." % [Dati.nome(p), Dati.nome(c), costo])
		if c == "URSS" and p == "GER":
			_attacco_all_urss()
		if p == "ITA" or c == "ITA":
			pass
	else:
		var mm: Dictionary = s["min"][c]
		_guerra(p, c)
		if mm["st"] == "neutrale":
			_log("%s dichiara guerra a %s (%d BRP)." % [Dati.nome(p), Dati.nome(c), costo])
			_attiva_minore(c, "alleati" if lato(p) == "asse" else "asse", p)
		elif mm["st"] == "attaccato":
			mm["nemici"].append(p)
			_log("%s dichiara guerra anche a %s (%d BRP)." % [Dati.nome(p), Dati.nome(c), costo])
		else:
			_log("%s dichiara guerra a %s (%d BRP)." % [Dati.nome(p), Dati.nome(c), costo])

## Barbarossa: nella versione base gli alleati minori dell'Asse entrano in guerra con la Germania
func _attacco_all_urss() -> void:
	if advanced():
		return
	for m in ["FIN", "HUN", "RUM"]:
		if s["min"][m]["st"] == "neutrale":
			_attiva_minore(m, "asse", "")
			_log("%s si schiera con l'Asse." % Dati.nome(m))

# =====================================================================================
# Sequenza del turno
# =====================================================================================

func potenze_del_lato(l: String) -> Array:
	var out := []
	for p in Dati.MAGGIORI:
		if lato(p) == l and not s["pot"][p]["arresa"]:
			out.append(p)
	return out

func _inizio_turno_giocatore() -> void:
	var l: String = s["lato"]
	for uid in s["u"]:
		var u: Dictionary = s["u"][uid]
		if lato(u["n"]) == l or (lato(u["n"]) == "" and false):
			u["mv"] = false
			u["at"] = false
			u["us"] = false
			u["sf"] = false
	for p in potenze_del_lato(l):
		s["pot"][p]["opz"] = ""
		s["sr_usati"][p] = 0
	s["sfond"] = []
	s["sfrutt"] = []
	s["attaccate"] = []
	s["avanzata"] = {}
	s["fase"] = "dichiarazioni"
	s["ultimo"] = {}
	_salta_fasi_vuote()

## passa alla fase successiva
func _prossima_fase() -> void:
	var i := FASI.find(s["fase"])
	if s["fase"] == "diplomazia":
		_risolvi_diplomazia()
		s["fase"] = "dichiarazioni"
		_salta_fasi_vuote()
		return
	if i < 0 or i >= FASI.size() - 1:
		_fine_turno_giocatore()
		return
	var prossima: String = FASI[i + 1]
	if s["fase"] == "combattimento":
		_dopo_combattimento()
	if prossima == "combattimento":
		s["fase"] = prossima
		_logoramento()
	elif prossima == "costruzione":
		_rifornimenti()
		_controlli_resa()
		s["fase"] = prossima
	else:
		s["fase"] = prossima
	if finita():
		return
	_salta_fasi_vuote()

func _salta_fasi_vuote() -> void:
	if finita():
		return
	match s["fase"]:
		"opzioni":
			var ci_sono := false
			for p in potenze_del_lato(s["lato"]):
				if attiva(p):
					ci_sono = true
			if not ci_sono:
				_prossima_fase()
		"sfruttamento":
			if s["sfrutt"].is_empty():
				_prossima_fase()
		"combattimento":
			var off := false
			for p in potenze_del_lato(s["lato"]):
				if s["pot"][p]["opz"] == "off":
					off = true
			if not off:
				_prossima_fase()

func _fine_turno_giocatore() -> void:
	_controlli_resa(true)
	if finita():
		return
	if int(s["meta"]) == 0:
		s["meta"] = 1
		s["lato"] = "alleati" if s["prima"] == "asse" else "asse"
		_inizio_turno_giocatore()
		return
	# fine del turno di gioco: stagione successiva
	s["meta"] = 0
	s["stag"] = int(s["stag"]) + 1
	s["turno"] = int(s["turno"]) + 1
	if int(s["stag"]) > 3:
		s["stag"] = 0
		s["anno"] = int(s["anno"]) + 1
	if int(s["anno"]) > int(s["fine_anno"]) or (int(s["anno"]) == int(s["fine_anno"]) and int(s["stag"]) > int(s["fine_stag"])):
		_vittoria_a_tempo()
		return
	_log("— %s —" % data_testo())
	_eventi_stagione()
	if finita():
		return
	if int(s["stag"]) == 0:
		_inizio_anno()
	s["lato"] = s["prima"]
	_inizio_turno_giocatore()
	if advanced() and int(s["stag"]) == 0 and not finita():
		s["fase"] = "diplomazia"
		s["dp_turno"] = "asse"

func _eventi_stagione() -> void:
	# Stati Uniti in guerra dall'inverno 1941 (Pearl Harbor)
	var anno := int(s["anno"])
	var st := int(s["stag"])
	if s["pot"]["USA"]["guerra"].is_empty() and (anno > 1941 or (anno == 1941 and st == 3)):
		for q in ["GER", "ITA"]:
			if not s["pot"][q]["arresa"]:
				_guerra("USA", q)
		s["pot"]["USA"]["brp"] = int(s["pot"]["USA"]["base"])
		_schiera_usa()
		_log("Pearl Harbor: gli Stati Uniti entrano in guerra contro l'Asse.")
	# L'URSS entra in guerra comunque nell'estate 1942
	if s["pot"]["URSS"]["guerra"].is_empty() and (anno > 1942 or (anno == 1942 and st >= 1)):
		_guerra("URSS", "GER")
		if not s["pot"]["ITA"]["arresa"] and attiva("ITA"):
			_guerra("URSS", "ITA")
		_log("L'Unione Sovietica entra in guerra contro la Germania.")
		_attacco_all_urss()
	# Bulgaria con l'Asse nella primavera 1941 (versione base)
	if not advanced() and anno >= 1941 and s["min"]["BUL"]["st"] == "neutrale":
		_attiva_minore("BUL", "asse", "")
		_log("La Bulgaria aderisce al Patto tripartito.")
	# chi muove per primo
	if st == 0 and anno >= 1942:
		var tot := {"asse": 0, "alleati": 0}
		for p in Dati.MAGGIORI:
			if not s["pot"][p]["arresa"] and attiva(p):
				tot[lato(p)] += int(s["pot"][p]["base"])
		s["prima"] = "asse" if tot["asse"] >= tot["alleati"] else "alleati"

## Inizio dell'anno (primavera): calcolo dei BRP
func _inizio_anno() -> void:
	var righe := []
	for p in Dati.MAGGIORI:
		var pot: Dictionary = s["pot"][p]
		if pot["arresa"]:
			continue
		if p == "USA" and pot["guerra"].is_empty():
			continue
		var rimasti: int = clampi(int(pot["brp"]), 0, int(pot["base"]))
		var crescita := int(floor(rimasti * Dati.CRESCITA[p] / 100.0))
		pot["base"] = int(pot["base"]) + crescita
		var conquiste := 0
		for m in s["min"]:
			var mm: Dictionary = s["min"][m]
			if mm["st"] == "conquistato" and mm["di"] == p:
				conquiste += int(Dati.MINORI.get(m, 0))
		# colonie altrui conquistate e colonie proprie perse
		var colonie := 0
		for c in Dati.COLONIE:
			var cap: String = D.capitali.get(c, "")
			if cap == "":
				continue
			var chi := controllo(cap)
			var vale: int = Dati.VALORE_COLONIE.get(c, 0)
			if chi == p and Dati.COLONIE[c] != p:
				colonie += vale
			elif chi != p and Dati.COLONIE[c] == p and lato(chi) != lato(p) and lato(chi) != "":
				colonie -= vale
		var perdite := 0
		for id in D.obiettivi:
			if D.esagoni[id]["n"] == p and lato(controllo(id)) != lato(p) and lato(controllo(id)) != "":
				perdite += 10
		for id in D.industrie:
			if p == "URSS" and lato(controllo(id)) == "asse":
				perdite += 5
		var totale: int = maxi(0, int(pot["base"]) + conquiste + colonie - perdite)
		# Advanced: guerra strategica e aiuti
		if advanced():
			if p == "GB" and in_guerra("GER", "GB") and int(s["anno"]) >= 1940:
				var sub := _dado() + _dado() + (2 if int(s["anno"]) <= 1942 else 0) - (2 if int(s["anno"]) >= 1943 else 0)
				totale -= maxi(0, sub)
				righe.append("sommergibili tedeschi: -%d BRP britannici" % maxi(0, sub))
			if p == "GER" and int(s["anno"]) >= 1943 and attiva("USA"):
				var bom := _dado() + _dado() + (int(s["anno"]) - 1943) * 3
				totale -= bom
				righe.append("bombardamenti alleati: -%d BRP tedeschi" % bom)
			if p == "GER" and lato(controllo(_id_citta("Ploesti"))) != "asse":
				totale -= 10
				righe.append("senza il petrolio di Ploesti: -10 BRP tedeschi")
		pot["brp"] = maxi(0, totale)
		righe.append("%s: base %d, disponibili %d" % [Dati.nome(p), pot["base"], pot["brp"]])
	# affitti e prestiti all'URSS
	if advanced() and attiva("USA") and attiva("URSS") and not s["pot"]["URSS"]["arresa"]:
		var aiuto := mini(20, int(s["pot"]["USA"]["brp"]))
		s["pot"]["USA"]["brp"] = int(s["pot"]["USA"]["brp"]) - aiuto
		s["pot"]["URSS"]["brp"] = int(s["pot"]["URSS"]["brp"]) + aiuto
		righe.append("Affitti e prestiti: %d BRP dagli Stati Uniti all'URSS" % aiuto)
	_log("Inizio anno %d. %s." % [int(s["anno"]), "; ".join(righe)])

# =====================================================================================
# Diplomazia (Advanced)
# =====================================================================================

func punti_diplomatici(l: String) -> int:
	var dp := 3
	var chiave := ["Paris", "London", "Warsaw", "Moscow", "Leningrad", "Stalingrad", "Rome", "Berlin", "Cairo", "Athens", "Belgrade"]
	for nm in chiave:
		var id := _id_citta(nm)
		if id == "":
			continue
		var orig: String = D.esagoni[id]["n"]
		if lato(controllo(id)) == l and lato(orig) != l:
			dp += 1
	return dp

func bersagli_diplomatici() -> Array:
	var out := []
	for m in ["SPA", "TUR", "SWE", "HUN", "RUM", "BUL", "FIN", "JUG", "GRE", "PER", "POR", "IRL"]:
		if s["min"][m]["st"] == "neutrale":
			out.append(m)
	return out

func _risolvi_diplomazia() -> void:
	var dp: Dictionary = s.get("dp", {})
	var righe := []
	for m in dp:
		var a: int = int(dp[m].get("asse", 0))
		var b: int = int(dp[m].get("alleati", 0))
		if a == 0 and b == 0:
			continue
		if s["min"][m]["st"] != "neutrale":
			continue
		var tiro := _dado() + _dado() + (a - b)
		var esito := "nessun effetto"
		var verso_asse := ["HUN", "RUM", "BUL", "FIN", "SPA", "TUR", "SWE", "JUG", "GRE", "PER", "IRL", "POR"]
		var verso_alleati := ["TUR", "GRE", "JUG", "PER", "SWE", "POR", "SPA"]
		var soglia := 12 if m in ["HUN", "RUM", "BUL", "FIN"] else 13
		if tiro >= soglia and verso_asse.has(m):
			_attiva_minore(m, "asse", "")
			esito = "si schiera con l'Asse"
		elif tiro <= 1 and verso_alleati.has(m) and int(s["anno"]) >= 1942:
			_attiva_minore(m, "alleati", "")
			esito = "si schiera con gli Alleati"
		righe.append("%s (tiro %d): %s" % [Dati.nome(m), tiro, esito])
	s["dp"] = {}
	if righe.size() > 0:
		_log("Diplomazia: " + "; ".join(righe) + ".")

# =====================================================================================
# Richieste e decisioni
# =====================================================================================

## La decisione che il gioco aspetta: {g: lato che decide, k: tipo, ...}
func richiesta() -> Dictionary:
	if finita():
		return {"g": "", "k": "fine"}
	var l: String = s["lato"]
	if s["fase"] == "diplomazia":
		var chi: String = s.get("dp_turno", "asse")
		return {"g": chi, "k": "diplomazia", "dp": punti_diplomatici(chi) - _dp_usati(chi), "bersagli": bersagli_diplomatici()}
	if not s["avanzata"].is_empty():
		return {"g": l, "k": "avanzata", "h": s["avanzata"]["h"], "u": s["avanzata"]["u"]}
	if s["fase"] == "opzioni":
		for p in potenze_del_lato(l):
			if attiva(p) and s["pot"][p]["opz"] == "":
				return {"g": l, "k": "opzioni", "p": p}
	return {"g": l, "k": s["fase"]}

func _dp_usati(l: String) -> int:
	var n := 0
	for m in s.get("dp", {}):
		n += int(s["dp"][m].get(l, 0))
	return n

## Applica una decisione. Restituisce {"ok": bool, "msg": testo, ...}
func applica(d: Dictionary) -> Dictionary:
	if finita():
		return {"ok": false, "msg": "partita finita"}
	var r := richiesta()
	var t: String = d.get("t", "")
	var res := {"ok": false, "msg": "decisione non valida"}
	match t:
		"fine":
			res = _fine_fase(r)
		"dp":
			if r["k"] == "diplomazia" and int(r["dp"]) > 0 and r["bersagli"].has(d.get("c", "")):
				var m: String = d["c"]
				if not s["dp"].has(m):
					s["dp"][m] = {}
				s["dp"][m][r["g"]] = int(s["dp"][m].get(r["g"], 0)) + 1
				res = {"ok": true}
		"dichiara":
			if r["k"] == "dichiarazioni" and lato(d.get("p", "")) == s["lato"] and dichiarazioni_possibili(d["p"]).has(d.get("c", "")):
				_dichiara(d["p"], d["c"])
				res = {"ok": true}
		"opz":
			if r["k"] == "opzioni" and r["p"] == d.get("p", ""):
				res = _scegli_opzione(d["p"], d.get("o", "pas"))
		"muovi":
			if r["k"] in ["movimento", "sfruttamento"]:
				res = _muovi(d.get("u", ""), d.get("h", ""), r["k"] == "sfruttamento")
		"attacca":
			if r["k"] in ["combattimento", "sfruttamento"]:
				res = _attacca(d.get("h", ""), d.get("u", []), d.get("av", []), r["k"] == "sfruttamento")
		"avanza":
			if r["k"] == "avanzata":
				res = _avanza(d.get("u", []))
		"costruisci":
			if r["k"] == "costruzione":
				res = _costruisci(d.get("p", ""), int(d.get("i", -1)), d.get("h", ""))
		"sr":
			if r["k"] == "ridispiegamento":
				res = _ridispiega(d.get("u", ""), d.get("h", ""))
	if res["ok"]:
		s["prog"] = int(s["prog"]) + 1
		_invalida()
	return res

func _fine_fase(r: Dictionary) -> Dictionary:
	match r["k"]:
		"diplomazia":
			if s.get("dp_turno", "asse") == "asse":
				s["dp_turno"] = "alleati"
			else:
				_prossima_fase()
		"opzioni":
			# le potenze che non hanno scelto passano
			for p in potenze_del_lato(s["lato"]):
				if attiva(p) and s["pot"][p]["opz"] == "":
					s["pot"][p]["opz"] = "pas"
			_prossima_fase()
		"avanzata":
			s["avanzata"] = {}
		_:
			_prossima_fase()
	return {"ok": true}

func _scegli_opzione(p: String, o: String) -> Dictionary:
	var costo := costo_offensiva(p)
	if o == "off" and not offensiva_permessa(p):
		return {"ok": false, "msg": "nel 1939 Francia e Gran Bretagna non possono scegliere l'offensiva (guerra fasulla)"}
	if o == "off" and int(s["pot"][p]["brp"]) < costo:
		return {"ok": false, "msg": "BRP insufficienti per l'offensiva"}
	s["pot"][p]["opz"] = o
	if o == "off":
		s["pot"][p]["brp"] = int(s["pot"][p]["brp"]) - costo
	_log("%s: %s." % [Dati.nome(p), NOMI_OPZIONE.get(o, o)])
	var tutte := true
	for q in potenze_del_lato(s["lato"]):
		if attiva(q) and s["pot"][q]["opz"] == "":
			tutte = false
	if tutte:
		_prossima_fase()
	return {"ok": true}

## «Guerra fasulla»: nel 1939 gli Alleati occidentali non lanciano offensive
func offensiva_permessa(p: String) -> bool:
	return not (p in ["GB", "FRA"] and int(s["anno"]) == 1939)

## Corpo di spedizione britannico: fino al 1941 al massimo 4 unità terrestri britanniche sul continente occidentale
func bef_pieno(id: String, n: String) -> bool:
	if comandante(n) != "GB" or int(s["anno"]) >= 1941 or not (D.esagoni[id]["n"] in ["FRA", "BEL", "NED", "LUX"]):
		return false
	var k := 0
	for uid in s["u"]:
		var u: Dictionary = s["u"][uid]
		if u["n"] == "GB" and _terrestre(u["t"]) and u["h"] != "USA" and D.esagoni.has(u["h"]) and D.esagoni[u["h"]]["n"] in ["FRA", "BEL", "NED", "LUX"]:
			k += 1
	return k >= 4

func costo_offensiva(p: String) -> int:
	var c := Dati.COSTO_OFFENSIVA
	if advanced() and lato(p) == "asse" and lato(controllo(_id_citta("Ploesti"))) != "asse" and int(s["anno"]) >= 1942:
		c += 5
	return c

## opzione che governa una nazione (i minori seguono il capofila del loro schieramento)
func opzione(n: String) -> String:
	var p := comandante(n)
	if p == "":
		return ""
	if not maggiore(n):
		# i minori aggrediti possono contrattaccare se una potenza del loro schieramento è in offensiva
		var o := ""
		for q in potenze_del_lato(lato(n)):
			if s["pot"][q]["opz"] == "off":
				return "off"
			if s["pot"][q]["opz"] != "":
				o = s["pot"][q]["opz"]
		return o
	return s["pot"][p]["opz"]

# =====================================================================================
# Movimento
# =====================================================================================

func costo_terreno(id: String) -> int:
	return 1 if int(D.esagoni[id]["t"]) == 0 else 2

## l'unità può muovere ora? (fase, schieramento, già mossa)
func puo_muovere(uid: String, sfruttamento := false) -> bool:
	if not s["u"].has(uid):
		return false
	var u: Dictionary = s["u"][uid]
	if lato(u["n"]) != s["lato"]:
		return false
	# dagli Stati Uniti partono per mare solo flotte e aviazione; le truppe usano il ridispiegamento
	if u["h"] == "USA" and (sfruttamento or not (u["t"] in ["flo", "avi"])):
		return false
	if sfruttamento:
		return s["sfrutt"].has(uid) and not u["sf"]
	if u["mv"]:
		return false
	return true

## esagoni raggiungibili: id -> costo. Include gli spostamenti via mare (valore -1).
func raggiungibili(uid: String, sfruttamento := false) -> Dictionary:
	var u: Dictionary = s["u"][uid]
	var n: String = u["n"]
	var out := {}
	if not puo_muovere(uid, sfruttamento):
		return out
	match u["t"]:
		"avi":
			return _raggiungibili_aria(uid)
		"flo":
			return _raggiungibili_mare(uid)
	var off := opzione(n) == "off"
	var mp: int = int(u["m"])
	var start: String = u["h"]
	var dist := {start: 0}
	var coda := [start]
	while coda.size() > 0:
		# estrae il minimo (pochi nodi: va bene una ricerca lineare)
		var bi := 0
		for i in range(1, coda.size()):
			if dist[coda[i]] < dist[coda[bi]]:
				bi = i
		var a: String = coda[bi]
		coda.remove_at(bi)
		if a != start and zoc(a, n):
			continue
		for b in D.esagoni[a]["terra"]:
			if not D.terra(b):
				continue
			if nemici_in(b, n):
				continue
			var c := controllo(b)
			if not _entrabile(n, c, off):
				continue
			var nd: int = dist[a] + costo_terreno(b)
			if nd > mp:
				continue
			if nd < dist.get(b, 999):
				dist[b] = nd
				coda.append(b)
	var dentro: bool = D.esagoni.has(start) and D.esagoni[start]["n"] in ["FRA", "BEL", "NED", "LUX"]
	for id in dist:
		if id != start and _impilabile(id, n, uid) and (dentro or not bef_pieno(id, n)):
			out[id] = dist[id]
	# trasporto via mare (non durante lo sfruttamento): da un porto amico con flotte sufficienti
	if not sfruttamento and D.porti.has(start) and amico(n, controllo(start)):
		var fl := _flotte_disponibili(start, comandante(n))
		if fl >= int(u["a"]):
			for id in _porti_e_coste_raggiungibili(start, 16, n):
				if out.has(id) or id == start or nemici_in(id, n):
					continue
				var c := controllo(id)
				if not _entrabile(n, c, off):
					continue
				if not _impilabile(id, n, uid) or bef_pieno(id, n):
					continue
				out[id] = -1
	return out

func _entrabile(n: String, c: String, off: bool) -> bool:
	if c == "" or amico(n, c):
		return true
	if in_guerra(n, c) or in_guerra(comandante(n), c):
		return off
	return false

func _impilabile(id: String, n: String, uid := "") -> bool:
	var k := 0
	for x in terrestri_in(id):
		if x != uid:
			k += 1
	return k < 2

func _raggiungibili_aria(uid: String) -> Dictionary:
	var u: Dictionary = s["u"][uid]
	var n: String = u["n"]
	var out := {}
	for id in D.esagoni:
		if not D.terra(id) or id == u["h"]:
			continue
		if u["h"] == "USA" and D.esagoni[id]["n"] != "GB":
			continue
		if u["h"] != "USA" and D.distanza(u["h"], id) > 8:
			continue
		if amico(n, controllo(id)) and not nemici_in(id, n):
			out[id] = D.distanza(u["h"], id) if u["h"] != "USA" else 1
	return out

func _raggiungibili_mare(uid: String) -> Dictionary:
	var u: Dictionary = s["u"][uid]
	var n: String = u["n"]
	var out := {}
	if u["h"] == "USA":
		# attraverso l'Atlantico: verso i porti amici della costa atlantica
		for id in D.porti:
			if int(D.esagoni[id]["c"]) <= 26 and amico(n, controllo(id)) and not nemici_in(id, n):
				out[id] = 1
		return out
	for id in _porti_e_coste_raggiungibili(u["h"], 20, n):
		if D.porti.has(id) and amico(n, controllo(id)) and not nemici_in(id, n):
			out[id] = 1
	return out

## esagoni costieri raggiungibili navigando al massimo per 'passi' esagoni di mare
## le flotte possono attraversare un porto amico per passare da un mare all'altro (canali, stretti,
## penisole come il Cotentin, Kiel, Gibilterra, Port Said): n è la nazione che naviga ("" = nessun passaggio)
## stretti che la griglia rappresenta come terra: il porto collega anche questi esagoni di mare
const PASSAGGI := {"AA7": ["BB9", "AA11", "AA6", "Z7"]}

func _porti_e_coste_raggiungibili(da: String, passi: int, n := "") -> Array:
	var dist := {}
	var coda := []
	for v in D.esagoni[da]["vicini"]:
		if D.esagoni[v]["t"] == 9:
			dist[v] = 1
			coda.append(v)
	var out := {}
	var attraversati := {da: true}
	# dal porto di partenza si raggiungono anche i mari dietro un esagono di terra amico
	if n != "" and D.porti.has(da):
		for c in D.esagoni[da]["vicini"]:
			if D.esagoni[c]["t"] != 9 and D.terra(c) and amico(n, controllo(c)) and not nemici_in(c, n):
				for e in D.esagoni[c]["vicini"]:
					if D.esagoni[e]["t"] == 9 and not dist.has(e):
						dist[e] = 2
						coda.append(e)
	# si parte da un porto-passaggio: anche i suoi mari aggiuntivi
	if n != "" and PASSAGGI.has(da):
		for c in PASSAGGI[da]:
			if not dist.has(c):
				dist[c] = 1
				coda.append(c)
	var i := 0
	while i < coda.size():
		var a: String = coda[i]
		i += 1
		var vic: Array = D.esagoni[a]["vicini"]
		if n != "":
			for pp in PASSAGGI:
				if PASSAGGI[pp].has(a):
					vic = vic + [pp]
		for b in vic:
			if D.esagoni[b]["t"] == 9:
				if not dist.has(b) and dist[a] < passi:
					dist[b] = dist[a] + 1
					coda.append(b)
			else:
				out[b] = true
				# passaggio attraverso un porto amico verso un altro mare
				if n != "" and D.porti.has(b) and not attraversati.has(b) and dist[a] + 1 < passi and amico(n, controllo(b)) and not nemici_in(b, n):
					attraversati[b] = true
					for c in PASSAGGI.get(b, []):
						if not dist.has(c):
							dist[c] = dist[a] + 2
							coda.append(c)
					for c in D.esagoni[b]["vicini"]:
						if D.esagoni[c]["t"] == 9:
							if not dist.has(c):
								dist[c] = dist[a] + 2
								coda.append(c)
						elif D.terra(c) and amico(n, controllo(c)) and not nemici_in(c, n):
							# un esagono di terra amico in più (la Rocca di Gibilterra, il canale di Suez)
							for e in D.esagoni[c]["vicini"]:
								if D.esagoni[e]["t"] == 9 and not dist.has(e):
									dist[e] = dist[a] + 3
									coda.append(e)
	return out.keys()

func _flotte_disponibili(porto: String, p: String) -> int:
	var tot := 0
	for uid in _occupazione().get(porto, []):
		var u: Dictionary = s["u"][uid]
		if u["t"] == "flo" and comandante(u["n"]) == p and not u["us"]:
			tot += int(u["a"])
	return tot

func _usa_flotte(porto: String, p: String, quanto: int) -> void:
	for uid in _occupazione().get(porto, []):
		var u: Dictionary = s["u"][uid]
		if quanto <= 0:
			break
		if u["t"] == "flo" and comandante(u["n"]) == p and not u["us"]:
			u["us"] = true
			quanto -= int(u["a"])

func _muovi(uid: String, dest: String, sfruttamento: bool) -> Dictionary:
	if not s["u"].has(uid):
		return {"ok": false, "msg": "unità inesistente"}
	var rr := raggiungibili(uid, sfruttamento)
	if not rr.has(dest):
		return {"ok": false, "msg": "esagono non raggiungibile"}
	var u: Dictionary = s["u"][uid]
	var da: String = u["h"]
	if int(rr[dest]) == -1:
		_usa_flotte(da, comandante(u["n"]), int(u["a"]))
		_log("%s salpa da %s e sbarca in %s." % [descrizione_unita(uid), _nome_es(da), _nome_es(dest)])
	u["h"] = dest
	if sfruttamento:
		u["sf"] = true
	else:
		u["mv"] = true
	_invalida()
	if _terrestre(u["t"]):
		_occupa(dest, u["n"])
	s["ultimo"] = {"k": "muovi", "u": uid, "da": da, "a": dest}
	return {"ok": true}

func _occupa(id: String, n: String) -> void:
	var c := controllo(id)
	if c == "" or c == n:
		return
	if in_guerra(n, c) or in_guerra(comandante(n), c):
		var nuovo := n
		if not maggiore(n):
			nuovo = comandante(n) if s["min"][n]["st"] == "alleato" else n
		s["ctrl"][id] = nuovo

func _nome_es(id: String) -> String:
	if id == "USA":
		return "Stati Uniti"
	var h: Dictionary = D.esagoni.get(id, {})
	if h.is_empty():
		return id
	return "%s (%s)" % [h["citta"], id] if h["citta"] != "" else id

func nome_esagono(id: String) -> String:
	return _nome_es(id)

# =====================================================================================
# Combattimento
# =====================================================================================

## unità che possono attaccare l'esagono bersaglio
func attaccanti_possibili(bersaglio: String, sfruttamento := false) -> Array:
	var out := []
	if not D.esagoni.has(bersaglio):
		return out
	var dif := terrestri_in(bersaglio)
	if dif.is_empty() or s["attaccate"].has(bersaglio):
		return out
	for v in D.esagoni[bersaglio]["terra"]:
		for uid in terrestri_in(v):
			var u: Dictionary = s["u"][uid]
			if lato(u["n"]) != s["lato"] or u["at"] or int(u["nr"]) > 0:
				continue
			if sfruttamento and not s["sfrutt"].has(uid):
				continue
			if opzione(u["n"]) != "off":
				continue
			var ok := true
			for d in dif:
				if not in_guerra(u["n"], s["u"][d]["n"]) and not in_guerra(comandante(u["n"]), s["u"][d]["n"]):
					ok = false
			if ok:
				out.append(uid)
	return out

## aviazione che può appoggiare un attacco sul bersaglio (raggio 4)
func aerei_possibili(bersaglio: String, l: String) -> Array:
	var out := []
	for uid in s["u"]:
		var u: Dictionary = s["u"][uid]
		if u["t"] != "avi" or u["us"] or lato(u["n"]) != l or u["h"] == "USA":
			continue
		if D.distanza(u["h"], bersaglio) <= 4 and attiva(u["n"]):
			if l != s["lato"] or opzione(u["n"]) == "off":
				out.append(uid)
	return out

## calcolo delle forze in un attacco
func valuta_attacco(bersaglio: String, att: Array, aerei: Array) -> Dictionary:
	var fa := 0
	var tutti_fiume := att.size() > 0
	for uid in att:
		fa += forza(uid)
		if not D.fiume_tra(s["u"][uid]["h"], bersaglio):
			tutti_fiume = false
	for uid in aerei:
		fa += forza(uid)
	var fd := 0
	var base := 0
	for uid in terrestri_in(bersaglio):
		fd += forza(uid)
	base = fd
	var molt := 1
	var motivo := ""
	if int(D.esagoni[bersaglio]["t"]) == 1:
		molt = 2
		motivo = "montagna"
	elif int(D.esagoni[bersaglio]["t"]) == 2:
		molt = 2
		motivo = "palude"
	elif tutti_fiume:
		molt = 2
		motivo = "fiume"
	fd *= molt
	# appoggio aereo difensivo: l'aviazione del difensore entro 4 esagoni, se non già usata
	var dif_lato := lato(controllo(bersaglio))
	if terrestri_in(bersaglio).size() > 0:
		dif_lato = lato(s["u"][terrestri_in(bersaglio)[0]]["n"])
	var aerei_dif := []
	var fdif := 0
	for uid in aerei_possibili(bersaglio, dif_lato):
		if fdif >= base:
			break
		aerei_dif.append(uid)
		fdif += forza(uid)
	fd += fdif
	var col := Dati.colonna_crt(float(fa), float(fd))
	var spost := 0
	if advanced() and int(s["stag"]) == 3 and s["lato"] == "asse" and D.esagoni[bersaglio]["n"] == "URSS":
		spost = -2 if int(s["anno"]) == 1941 else -1
	if col >= 0:
		col = clampi(col + spost, 0, 7)
	return {"att": fa, "dif": fd, "base": base, "col": col, "molt": molt, "motivo": motivo, "aerei_dif": aerei_dif, "spost": spost}

func _attacca(bersaglio: String, att: Array, aerei: Array, sfruttamento: bool) -> Dictionary:
	var possibili := attaccanti_possibili(bersaglio, sfruttamento)
	if possibili.is_empty():
		return {"ok": false, "msg": "nessun attacco possibile"}
	var a := []
	for uid in att:
		if possibili.has(uid) and not a.has(uid):
			a.append(uid)
	if a.is_empty():
		return {"ok": false, "msg": "nessuna unità attaccante valida"}
	if not cooperazione_ok(a):
		return {"ok": false, "msg": "fino al 1941 britannici e francesi non possono attaccare insieme"}
	var av := []
	var ap := aerei_possibili(bersaglio, s["lato"])
	for uid in aerei:
		if ap.has(uid) and not av.has(uid):
			av.append(uid)
	var v := valuta_attacco(bersaglio, a, av)
	if int(v["col"]) < 0:
		return {"ok": false, "msg": "rapporto inferiore a 1 contro 4"}
	for uid in a:
		s["u"][uid]["at"] = true
	for uid in av:
		s["u"][uid]["us"] = true
	for uid in v["aerei_dif"]:
		s["u"][uid]["us"] = true
	s["attaccate"].append(bersaglio)
	var dado := _dado()
	var esito: String = Dati.CRT[dado - 1][int(v["col"])]
	var difensori := terrestri_in(bersaglio)
	var naz_dif := ""
	if difensori.size() > 0:
		naz_dif = s["u"][difensori[0]]["n"]
	var testo := "Attacco su %s: %d contro %d (%s%s), dado %d: %s" % [_nome_es(bersaglio), v["att"], v["dif"], Dati.COLONNE[int(v["col"])],
		(", " + v["motivo"]) if v["motivo"] != "" else "", dado, _testo_esito(esito)]
	var corazzati := false
	for uid in a:
		if s["u"][uid]["t"] == "cor":
			corazzati = true
	var risultato := {"bersaglio": bersaglio, "dado": dado, "esito": esito, "att": v["att"], "dif": v["dif"], "col": v["col"], "perdite_att": [], "perdite_dif": []}
	var vuoto := false
	match esito:
		"D":
			for uid in difensori:
				risultato["perdite_dif"].append(descrizione_unita(uid))
				_elimina(uid)
			vuoto = true
		"A":
			for uid in a:
				risultato["perdite_att"].append(descrizione_unita(uid))
				_elimina(uid)
		"Ex":
			for uid in difensori:
				risultato["perdite_dif"].append(descrizione_unita(uid))
				_elimina(uid)
			risultato["perdite_att"] = _perdite(a, av, int(v["base"]))
			vuoto = true
		_:
			# contrattacco: il difensore attacca a sua volta gli attaccanti
			var n := int(esito.substr(2)) if esito.length() > 2 else 0
			var fd := 0
			for uid in difensori:
				fd += forza(uid)
			var fa := 0
			for uid in a:
				fa += forza(uid)
			var col := Dati.colonna_crt(float(fd), float(fa))
			if col < 0:
				col = 0
			col = clampi(col - n, 0, 7)
			var d2 := _dado()
			var e2: String = Dati.CRT[d2 - 1][col]
			testo += "; contrattacco %s, dado %d: " % [Dati.COLONNE[col], d2]
			match e2:
				"D":
					testo += "attaccanti eliminati"
					for uid in a:
						risultato["perdite_att"].append(descrizione_unita(uid))
						_elimina(uid)
				"A":
					testo += "il contrattacco fallisce, difensori eliminati"
					for uid in difensori:
						risultato["perdite_dif"].append(descrizione_unita(uid))
						_elimina(uid)
					vuoto = true
				_:
					testo += "scambio"
					for uid in difensori:
						risultato["perdite_dif"].append(descrizione_unita(uid))
						_elimina(uid)
					risultato["perdite_att"] = _perdite(a, av, fd)
					vuoto = true
	_log(testo + ".")
	risultato["testo"] = testo
	var superstiti := []
	for uid in a:
		if s["u"].has(uid):
			superstiti.append(uid)
	if vuoto and superstiti.size() > 0 and terrestri_in(bersaglio).is_empty():
		s["avanzata"] = {"h": bersaglio, "u": superstiti, "sf": (corazzati and not sfruttamento)}
	elif vuoto and terrestri_in(bersaglio).is_empty() and naz_dif != "":
		pass
	s["ultimo"] = {"k": "combattimento", "r": risultato}
	_invalida()
	return {"ok": true, "risultato": risultato}

## Cooperazione anglo-francese: fino al 1941 le unità britanniche e francesi non attaccano insieme
func cooperazione_ok(att: Array) -> bool:
	if int(s["anno"]) >= 1941:
		return true
	var gb := false
	var fr := false
	for uid in att:
		var c := comandante(s["u"][uid]["n"])
		if c == "GB":
			gb = true
		elif c == "FRA":
			fr = true
	return not (gb and fr)

func _testo_esito(e: String) -> String:
	match e:
		"D": return "difensore eliminato"
		"A": return "attaccante eliminato"
		"Ex": return "scambio"
	return "contrattacco"

## l'attaccante perde almeno 'quanto' fattori, scegliendo le unità in modo da sprecare meno
func _perdite(att: Array, aerei: Array, quanto: int) -> Array:
	var tutte := att.duplicate()
	tutte.append_array(aerei)
	var perse := []
	if quanto <= 0:
		return perse
	# prima i rimpiazzi e la fanteria più debole, i corazzati per ultimi
	tutte.sort_custom(func(x, y): return _peso_perdita(x) < _peso_perdita(y))
	var resto := quanto
	# cerca un'unità sola che basti, la più piccola
	var migliore := ""
	for uid in tutte:
		if forza(uid) >= resto and (migliore == "" or _peso_perdita(uid) < _peso_perdita(migliore)):
			migliore = uid
	var somma_piccole := 0
	for uid in tutte:
		somma_piccole += forza(uid)
	var scelta := []
	for uid in tutte:
		if resto <= 0:
			break
		scelta.append(uid)
		resto -= forza(uid)
	if migliore != "" and _peso_perdita(migliore) <= _peso_scelta(scelta):
		scelta = [migliore]
	for uid in scelta:
		perse.append(descrizione_unita(uid))
		_elimina(uid)
	return perse

func _peso_perdita(uid: String) -> float:
	var u: Dictionary = s["u"][uid]
	var k := {"rim": 0.8, "fan": 1.0, "par": 1.6, "cor": 2.0, "avi": 5.0}
	return float(u["a"]) * k.get(u["t"], 1.0)

func _peso_scelta(sc: Array) -> float:
	var t := 0.0
	for uid in sc:
		t += _peso_perdita(uid)
	return t

func _avanza(unita: Array) -> Dictionary:
	var av: Dictionary = s["avanzata"]
	var h: String = av["h"]
	var n := 0
	for uid in unita:
		if not av["u"].has(uid) or not s["u"].has(uid):
			continue
		if not _impilabile(h, s["u"][uid]["n"], uid):
			break
		s["u"][uid]["h"] = h
		_invalida()
		_occupa(h, s["u"][uid]["n"])
		n += 1
		if av.get("sf", false) and s["u"][uid]["t"] == "cor":
			if not s["sfrutt"].has(uid):
				s["sfrutt"].append(uid)
			s["u"][uid]["sf"] = false
			if not s["sfond"].has(h):
				s["sfond"].append(h)
	if n > 0:
		_log("%d unità avanzano in %s%s." % [n, _nome_es(h), " (sfondamento)" if s["sfond"].has(h) else ""])
	s["avanzata"] = {}
	return {"ok": true}

## Logoramento: per ogni potenza che lo ha scelto, a inizio fase di combattimento
func _logoramento() -> void:
	for p in potenze_del_lato(s["lato"]):
		if s["pot"][p]["opz"] != "log":
			continue
		var fattori := 0
		var nemici := {}
		var vuoti := {}
		for uid in s["u"]:
			var u: Dictionary = s["u"][uid]
			if comandante(u["n"]) != p or not _terrestre(u["t"]) or u["h"] == "USA":
				continue
			var contatto := false
			for v in D.esagoni[u["h"]]["terra"]:
				for x in terrestri_in(v):
					if in_guerra(u["n"], s["u"][x]["n"]):
						contatto = true
						nemici[x] = true
				var c := controllo(v)
				if c != "" and in_guerra(p, c) and terrestri_in(v).is_empty() and D.terra(v):
					vuoti[v] = true
			if contatto:
				fattori += forza(uid)
		if fattori == 0:
			_log("%s: logoramento senza contatto con il nemico." % Dati.nome(p))
			continue
		var col := mini(6, int((fattori - 1) / 10))
		var dado := _dado()
		var r: Array = Dati.LOGORAMENTO[dado - 1][col]
		var c_perdite: int = r[0]
		var h_esagoni: int = r[1]
		var lista := nemici.keys()
		lista.sort_custom(func(x, y): return forza(x) < forza(y))
		var eliminati := []
		var resto := c_perdite
		for uid in lista:
			if resto <= 0:
				break
			if forza(uid) <= resto or eliminati.is_empty():
				resto -= forza(uid)
				eliminati.append(descrizione_unita(uid))
				_elimina(uid)
		var presi := []
		var vv := vuoti.keys()
		vv.sort_custom(func(x, y): return _valore_esagono(x) > _valore_esagono(y))
		for id in vv:
			if presi.size() >= h_esagoni:
				break
			if terrestri_in(id).is_empty():
				s["ctrl"][id] = p
				presi.append(_nome_es(id))
		_log("%s, logoramento con %d fattori (dado %d): %d C / %d H. %s%s" % [Dati.nome(p), fattori, dado, c_perdite, h_esagoni,
			("Eliminate: " + ", ".join(eliminati) + ". ") if eliminati.size() > 0 else "", ("Esagoni presi: " + ", ".join(presi) + ".") if presi.size() > 0 else ""])

func _valore_esagono(id: String) -> int:
	var h: Dictionary = D.esagoni[id]
	var v := 1
	if h["citta"] != "":
		v += 2
	if str(h["tipo"]).contains("O"):
		v += 5
	if str(h["tipo"]).contains("C"):
		v += 4
	return v

func _dopo_combattimento() -> void:
	s["avanzata"] = {}

# =====================================================================================
# Rifornimento
# =====================================================================================

## esagoni riforniti per lo schieramento l
func esagoni_riforniti(l: String) -> Dictionary:
	var fonti := []
	for id in s["ctrl"]:
		var c: String = s["ctrl"][id]
		if lato(c) != l or not attiva(c) and not maggiore(c):
			continue
		var h: Dictionary = D.esagoni[id]
		if h["citta"] == "":
			continue
		# città della propria patria, capitali e porti controllati
		if h["n"] == c or str(h["tipo"]).contains("C") or D.porti.has(id):
			if not _nemici_lato_in(id, l):
				fonti.append(id)
	var ok := {}
	var coda := fonti.duplicate()
	for f in fonti:
		ok[f] = true
	var i := 0
	while i < coda.size():
		var a: String = coda[i]
		i += 1
		for b in D.esagoni[a]["terra"]:
			if ok.has(b) or not D.terra(b):
				continue
			if _nemici_lato_in(b, l):
				continue
			var c := controllo(b)
			var amica := lato(c) == l
			var mie := false
			for x in terrestri_in(b):
				if lato(s["u"][x]["n"]) == l:
					mie = true
			if not amica and not mie:
				continue
			if not mie and _zoc_lato(b, l):
				continue
			ok[b] = true
			coda.append(b)
	return ok

func _nemici_lato_in(id: String, l: String) -> bool:
	for x in terrestri_in(id):
		var lx := lato(s["u"][x]["n"])
		if lx != "" and lx != l:
			return true
	return false

func _zoc_lato(id: String, l: String) -> bool:
	for v in D.esagoni[id]["terra"]:
		if _nemici_lato_in(v, l):
			return true
	return false

func _rifornimenti() -> void:
	var l: String = s["lato"]
	var ok := esagoni_riforniti(l)
	var eliminati := []
	for uid in s["u"].keys():
		var u: Dictionary = s["u"][uid]
		if lato(u["n"]) != l or u["h"] == "USA" or u["t"] == "flo":
			continue
		if ok.has(u["h"]):
			u["nr"] = 0
		else:
			u["nr"] = int(u["nr"]) + 1
			if int(u["nr"]) >= 2:
				eliminati.append(descrizione_unita(uid))
				_elimina(uid)
	if eliminati.size() > 0:
		_log("Senza rifornimenti, eliminate: %s." % ", ".join(eliminati))
	# gli esagoni nemici isolati e vuoti passano a chi li circonda? (non applicato)

# =====================================================================================
# Conquiste e rese
# =====================================================================================

func _controlli_resa(fine_turno := false) -> void:
	# paesi minori conquistati
	for m in s["min"]:
		var mm: Dictionary = s["min"][m]
		if not (mm["st"] in ["attaccato", "alleato", "neutrale"]):
			continue
		var cap: String = D.capitali.get(m, "")
		if cap == "":
			continue
		var c := controllo(cap)
		if c == m or c == "" or lato(c) == "":
			continue
		if in_guerra(c, m) or in_guerra(comandante(c), m):
			_conquista_minore(m, c if maggiore(c) else comandante(c))
	# potenze maggiori: si arrendono se alla fine del proprio turno la capitale è ancora in mano nemica
	var l: String = s["lato"]
	if not fine_turno:
		return
	if l == "alleati":
		_controlla_resa("FRA", "Paris")
		_controlla_resa("GB", "London")
	else:
		_controlla_resa("ITA", "Rome")
		_controlla_resa("GER", "Berlin")
		# la Francia cade appena l'Asse occupa Parigi con le sue truppe alla fine del proprio turno
		if not s["pot"]["FRA"]["arresa"] and attiva("FRA"):
			var parigi := _id_citta("Paris")
			if lato(controllo(parigi)) == "asse":
				for x in terrestri_in(parigi):
					if lato(s["u"][x]["n"]) == "asse":
						_resa("FRA")
						break
	if l == "alleati" and not s["pot"]["URSS"]["arresa"] and attiva("URSS"):
		var mosca := lato(controllo(_id_citta("Moscow"))) == "asse"
		var altre := 0
		for nm in ["Leningrad", "Stalingrad", "Kharkov", "Kiev"]:
			if lato(controllo(_id_citta(nm))) == "asse":
				altre += 1
		if mosca and altre >= 2:
			_resa("URSS")

func _conquista_minore(m: String, chi: String) -> void:
	var mm: Dictionary = s["min"][m]
	mm["st"] = "conquistato"
	mm["di"] = chi
	var rimossi := 0
	for uid in s["u"].keys():
		if s["u"][uid]["n"] == m:
			s["u"].erase(uid)
			rimossi += 1
	_invalida()
	for id in s["ctrl"]:
		if s["ctrl"][id] == m:
			s["ctrl"][id] = chi
	_log("%s è conquistata da %s." % [Dati.nome(m), Dati.nome(chi)])
	# Patto Molotov-Ribbentrop: alla caduta della Polonia l'URSS prende la Polonia orientale e i Paesi baltici
	if m == "POL" and lato(chi) == "asse" and not in_guerra("GER", "URSS"):
		for id in D.polonia_est:
			if terrestri_in(id).is_empty() or true:
				for uid in terrestri_in(id):
					if lato(s["u"][uid]["n"]) == "asse":
						# le unità tedesche si ritirano verso ovest
						s["u"][uid]["h"] = _ritirata(id, s["u"][uid]["n"])
				s["ctrl"][id] = "URSS"
		if s["min"]["BAL"]["st"] == "neutrale":
			s["min"]["BAL"]["st"] = "conquistato"
			s["min"]["BAL"]["di"] = "URSS"
			for id in s["ctrl"]:
				if s["ctrl"][id] == "BAL":
					s["ctrl"][id] = "URSS"
		_invalida()
		_log("Patto tedesco-sovietico: l'URSS occupa la Polonia orientale e i Paesi baltici.")

func _ritirata(da: String, n: String) -> String:
	var best := da
	var bd := 999
	for id in s["ctrl"]:
		if s["ctrl"][id] == "GER" and D.terra(id) and terrestri_in(id).size() < 2:
			var d := D.distanza(da, id)
			if d < bd:
				bd = d
				best = id
	return best

func _controlla_resa(p: String, citta: String) -> void:
	if s["pot"][p]["arresa"] or not attiva(p):
		return
	var id := _id_citta(citta)
	var c := controllo(id)
	if c != "" and lato(c) != lato(p) and lato(c) != "":
		_resa(p)

func _resa(p: String) -> void:
	s["pot"][p]["arresa"] = true
	var vincitore := "GER" if lato(p) == "alleati" else ("GB" if not s["pot"]["GB"]["arresa"] else "USA")
	for uid in s["u"].keys():
		if s["u"][uid]["n"] == p:
			s["u"].erase(uid)
	_invalida()
	match p:
		"FRA":
			# nasce la Francia di Vichy: il sud della Francia e le colonie restano neutrali
			s["min"]["VIC"]["st"] = "neutrale"
			s["min"]["VIC"]["lato"] = ""
			for id in s["ctrl"]:
				var h: Dictionary = D.esagoni[id]
				if s["ctrl"][id] != "FRA":
					continue
				if D.vichy.has(id) or (h["n"] in ["MAR", "ALG", "TUN", "LIS"]):
					s["ctrl"][id] = "VIC"
				else:
					s["ctrl"][id] = vincitore
			_log("La Francia si arrende. Nasce la Francia di Vichy, neutrale, con il sud del paese e le colonie.")
		"ITA":
			for id in s["ctrl"]:
				if s["ctrl"][id] == "ITA":
					s["ctrl"][id] = "GER"
			_log("L'Italia si arrende agli Alleati; i tedeschi occupano il resto del paese.")
		"GB":
			_log("La Gran Bretagna si arrende: Londra è caduta.")
			s["fine"] = "Vittoria decisiva dell'Asse: la Gran Bretagna si è arresa."
		"GER":
			_log("La Germania si arrende: Berlino è caduta.")
			s["fine"] = "Vittoria decisiva degli Alleati: la Germania si è arresa."
		"URSS":
			for id in s["ctrl"]:
				if s["ctrl"][id] == "URSS":
					s["ctrl"][id] = "GER"
			_log("L'Unione Sovietica chiede la pace: la Germania occupa il territorio sovietico in Europa.")
	for q in Dati.MAGGIORI:
		s["pot"][q]["guerra"].erase(p)
	s["pot"][p]["guerra"] = []
	if not finita():
		_controlla_vittoria_totale()

func _controlla_vittoria_totale() -> void:
	var asse_vivi := false
	for p in ["GER", "ITA"]:
		if not s["pot"][p]["arresa"]:
			asse_vivi = true
	if not asse_vivi:
		s["fine"] = "Vittoria degli Alleati."

## obiettivi controllati dall'Asse
func obiettivi_asse() -> int:
	var n := 0
	for id in D.obiettivi:
		if lato(controllo(id)) == "asse":
			n += 1
	return n

func _vittoria_a_tempo() -> void:
	var n := obiettivi_asse()
	var t := ""
	if n >= 22:
		t = "Vittoria strategica dell'Asse"
	elif n >= 15:
		t = "Vittoria marginale dell'Asse"
	elif n >= 10:
		t = "Pareggio"
	elif n >= 6:
		t = "Vittoria marginale degli Alleati"
	else:
		t = "Vittoria strategica degli Alleati"
	s["fine"] = "%s: a fine guerra l'Asse controlla %d esagoni obiettivo su %d." % [t, n, D.obiettivi.size()]
	_log(s["fine"])

# =====================================================================================
# Costruzione e ridispiegamento
# =====================================================================================

## potenze che possono costruire nel turno (anche neutrali, tranne gli USA prima della guerra)
func costruttori() -> Array:
	var out := []
	for p in potenze_del_lato(s["lato"]):
		if p == "USA" and s["pot"]["USA"]["guerra"].is_empty():
			continue
		out.append(p)
	return out

func costo_unita(e: Array) -> int:
	return int(Dati.COSTO[e[0]]) * int(e[1])

## esagoni dove la potenza p può piazzare una nuova unità di tipo t
func luoghi_costruzione(p: String, t: String) -> Array:
	var out := []
	if p == "USA":
		return ["USA"]
	var rif := esagoni_riforniti(lato(p))
	for id in s["ctrl"]:
		if s["ctrl"][id] != p:
			continue
		var h: Dictionary = D.esagoni[id]
		if h["citta"] == "" or h["n"] != p or not rif.has(id):
			continue
		if t == "flo" and not D.porti.has(id):
			continue
		if _terrestre(t) and not _impilabile(id, p):
			continue
		out.append(id)
	return out

func _costruisci(p: String, i: int, h: String) -> Dictionary:
	if not costruttori().has(p):
		return {"ok": false, "msg": "questa potenza non può costruire"}
	var pool: Array = s["pool"][p]
	if i < 0 or i >= pool.size():
		return {"ok": false, "msg": "unità non disponibile"}
	var e: Array = pool[i]
	var c := costo_unita(e)
	if int(s["pot"][p]["brp"]) < c:
		return {"ok": false, "msg": "BRP insufficienti"}
	if not luoghi_costruzione(p, e[0]).has(h):
		return {"ok": false, "msg": "luogo non valido"}
	pool.remove_at(i)
	s["pot"][p]["brp"] = int(s["pot"][p]["brp"]) - c
	var uid := _nuova_unita(p, e[0], int(e[1]), int(e[2]), h)
	s["u"][uid]["mv"] = true
	_log("%s costruisce: %s in %s (%d BRP)." % [Dati.nome(p), descrizione_unita(uid), _nome_es(h), c])
	return {"ok": true, "u": uid}

func sr_rimasti(p: String) -> int:
	return int(Dati.SR.get(p, 0)) - int(s["sr_usati"].get(p, 0))

## destinazioni del ridispiegamento strategico
func destinazioni_sr(uid: String) -> Array:
	var out := []
	if not s["u"].has(uid):
		return out
	var u: Dictionary = s["u"][uid]
	var n: String = u["n"]
	var p := comandante(n)
	if lato(n) != s["lato"] or not maggiore(n) or sr_rimasti(p) <= 0 or u["t"] == "flo" or u["at"]:
		return out
	var l := lato(n)
	if u["h"] == "USA":
		for id in D.porti:
			if amico(n, controllo(id)) and not _nemici_lato_in(id, l) and (not _terrestre(u["t"]) or _impilabile(id, n)) and not _zoc_lato(id, l):
				out.append(id)
		return out
	if _zoc_lato(u["h"], l):
		return out
	# via terra attraverso territorio amico senza zone di controllo nemiche
	var visti := {u["h"]: true}
	var coda := [u["h"]]
	var i := 0
	while i < coda.size():
		var a: String = coda[i]
		i += 1
		for b in D.esagoni[a]["terra"]:
			if visti.has(b) or not D.terra(b):
				continue
			if not amico(n, controllo(b)) or _nemici_lato_in(b, l) or _zoc_lato(b, l):
				continue
			visti[b] = true
			coda.append(b)
	# via mare tra porti amici, se la potenza ha flotte
	var flotte := 0
	for x in s["u"]:
		if s["u"][x]["t"] == "flo" and comandante(s["u"][x]["n"]) == p:
			flotte += forza(x)
	if D.porti.has(u["h"]) and flotte >= forza(uid):
		for id in _porti_e_coste_raggiungibili(u["h"], 90, n):
			if D.porti.has(id) and amico(n, controllo(id)) and not _nemici_lato_in(id, l) and not _zoc_lato(id, l):
				visti[id] = true
	var dentro: bool = D.esagoni.has(u["h"]) and D.esagoni[u["h"]]["n"] in ["FRA", "BEL", "NED", "LUX"]
	for id in visti:
		if id == u["h"]:
			continue
		if _terrestre(u["t"]) and not _impilabile(id, n, uid):
			continue
		if _terrestre(u["t"]) and not dentro and bef_pieno(id, n):
			continue
		out.append(id)
	return out

func _ridispiega(uid: String, h: String) -> Dictionary:
	if not destinazioni_sr(uid).has(h):
		return {"ok": false, "msg": "ridispiegamento non valido"}
	var u: Dictionary = s["u"][uid]
	var p := comandante(u["n"])
	var da: String = u["h"]
	u["h"] = h
	s["sr_usati"][p] = int(s["sr_usati"].get(p, 0)) + 1
	_invalida()
	_log("Ridispiegamento: %s da %s a %s." % [descrizione_unita(uid), _nome_es(da), _nome_es(h)])
	s["ultimo"] = {"k": "muovi", "u": uid, "da": da, "a": h}
	return {"ok": true}

# =====================================================================================
# Salvataggio
# =====================================================================================

func esporta() -> Dictionary:
	return s.duplicate(true)

func importa(st: Dictionary) -> void:
	s = st.duplicate(true)
	# JSON trasforma gli interi in float: li riporta a interi dove servono
	for k in ["anno", "stag", "turno", "meta", "rng", "prog", "nid", "fine_anno", "fine_stag"]:
		if s.has(k):
			s[k] = int(s[k])
	for p in s["pot"]:
		for k in ["base", "brp"]:
			s["pot"][p][k] = int(s["pot"][p][k])
	for uid in s["u"]:
		var u: Dictionary = s["u"][uid]
		u["a"] = int(u["a"])
		u["m"] = int(u["m"])
		u["nr"] = int(u["nr"])
	for n in s["pool"]:
		var nuovo := []
		for e in s["pool"][n]:
			nuovo.append([str(e[0]), int(e[1]), int(e[2])])
		s["pool"][n] = nuovo
	for p in s.get("sr_usati", {}):
		s["sr_usati"][p] = int(s["sr_usati"][p])
	_invalida()
