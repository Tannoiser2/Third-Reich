## Dati fissi del gioco: mappa a esagoni, potenze, paesi minori, tabelle.
## Gli esagoni hanno lo stesso sistema di coordinate in entrambe le mappe (base e Advanced):
## righe A…Z, AA…NN e colonne numerate; le due immagini differiscono solo per la griglia in pixel.
class_name Dati
extends RefCounted

const LATI := ["asse", "alleati"]
const MAGGIORI := ["GER", "ITA", "GB", "FRA", "URSS", "USA"]
const LATO_DI := {"GER": "asse", "ITA": "asse", "GB": "alleati", "FRA": "alleati", "URSS": "alleati", "USA": "alleati"}
## capofila di ogni schieramento (per i paesi minori alleati)
const CAPO := {"asse": "GER", "alleati": "GB"}

const NOMI := {
	"GER": "Germania", "ITA": "Italia", "GB": "Gran Bretagna", "FRA": "Francia", "URSS": "Unione Sovietica", "USA": "Stati Uniti",
	"POL": "Polonia", "NOR": "Norvegia", "SWE": "Svezia", "FIN": "Finlandia", "DAN": "Danimarca", "NED": "Paesi Bassi",
	"BEL": "Belgio", "LUX": "Lussemburgo", "IRL": "Irlanda", "SPA": "Spagna", "POR": "Portogallo", "HUN": "Ungheria",
	"RUM": "Romania", "JUG": "Jugoslavia", "BUL": "Bulgaria", "ALB": "Albania", "GRE": "Grecia", "TUR": "Turchia",
	"BAL": "Stati baltici", "MAR": "Marocco", "ALG": "Algeria", "TUN": "Tunisia", "LIB": "Libia", "EGI": "Egitto",
	"LIS": "Libano-Siria", "PAL": "Palestina", "TRA": "Transgiordania", "IRQ": "Iraq", "PER": "Persia", "ARA": "Arabia",
	"KUW": "Kuwait", "VIC": "Francia di Vichy",
}
const AGGETTIVI := {"GER": "tedesca", "ITA": "italiana", "GB": "britannica", "FRA": "francese", "URSS": "sovietica", "USA": "americana"}

## Colonie e possedimenti: territorio controllato da una potenza maggiore a inizio partita
const COLONIE := {"MAR": "FRA", "ALG": "FRA", "TUN": "FRA", "LIS": "FRA", "LIB": "ITA", "ALB": "ITA",
	"EGI": "GB", "PAL": "GB", "TRA": "GB", "IRQ": "GB", "KUW": "GB"}
## Paesi minori indipendenti (neutrali a inizio partita) e valore in BRP
const MINORI := {"POL": 25, "NOR": 10, "SWE": 15, "FIN": 10, "DAN": 10, "NED": 10, "BEL": 15, "LUX": 5,
	"IRL": 5, "SPA": 30, "POR": 5, "HUN": 10, "RUM": 15, "JUG": 20, "BUL": 10, "GRE": 10, "TUR": 30,
	"BAL": 15, "PER": 10, "ARA": 0}
## valore in BRP delle colonie (contano per chi le controlla)
const VALORE_COLONIE := {"MAR": 5, "ALG": 5, "TUN": 5, "LIS": 5, "LIB": 5, "ALB": 5, "EGI": 5, "PAL": 5, "TRA": 5, "IRQ": 10, "KUW": 0, "VIC": 0}

## BRP iniziali (base) e crescita annua in percentuale sui BRP non spesi
const BRP_BASE := {"GER": 150, "ITA": 75, "GB": 125, "FRA": 85, "URSS": 90, "USA": 135}
const CRESCITA := {"GER": 40, "ITA": 20, "GB": 40, "FRA": 30, "URSS": 30, "USA": 60}
## Ridispiegamenti strategici per turno
const SR := {"GER": 6, "ITA": 3, "GB": 4, "FRA": 3, "URSS": 4, "USA": 5}

## Costo in BRP per fattore
const COSTO := {"fan": 1, "rim": 1, "cor": 2, "par": 2, "avi": 5, "flo": 3}
const COSTO_GUERRA_MAGGIORE := 35
const COSTO_GUERRA_MINORE := 10
const COSTO_OFFENSIVA := 15

const NOMI_TIPO := {"fan": "fanteria", "cor": "corazzati", "par": "aviotrasportati", "rim": "rimpiazzi", "avi": "aviazione", "flo": "flotta"}
const STAGIONI := ["Primavera", "Estate", "Autunno", "Inverno"]
const TERRENO := ["pianura", "montagna", "palude"]

## Tabella dei risultati del combattimento: righe = dado 1..6, colonne = 1-4,1-3,1-2,1-1,2-1,3-1,4-1,5-1
const COLONNE := ["1-4", "1-3", "1-2", "1-1", "2-1", "3-1", "4-1", "5-1"]
const CRT := [
	["Ex", "Ex", "Ex", "Ex", "Ex", "Ex", "Ex", "Ex"],
	["A", "Ex", "Ex", "CA", "CA2", "CA2", "CA3", "D"],
	["A", "A", "CA", "CA", "CA2", "CA3", "D", "D"],
	["A", "A", "A", "Ex", "CA1", "D", "D", "D"],
	["A", "A", "A", "A", "D", "D", "D", "D"],
	["A", "A", "A", "D", "D", "D", "D", "D"],
]
## Tabella del logoramento: colonne per fattori impegnati 1-10, 11-20 … 61+; valori [C, H]
const LOGORAMENTO := [
	[[1, 0], [2, 1], [3, 2], [4, 3], [5, 4], [6, 4], [7, 4]],
	[[1, 0], [2, 0], [3, 1], [4, 2], [5, 3], [6, 3], [7, 3]],
	[[0, 0], [1, 1], [3, 0], [4, 1], [5, 2], [6, 2], [7, 2]],
	[[0, 0], [1, 0], [2, 1], [3, 1], [4, 1], [5, 2], [6, 2]],
	[[0, 0], [1, 0], [2, 0], [3, 0], [3, 1], [4, 1], [5, 2]],
	[[0, 0], [0, 0], [1, 0], [2, 0], [3, 0], [4, 1], [4, 2]],
]

const LETTERE := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var esagoni := {}      # id -> {id, r, c, t, n, citta, tipo, costa, vicini[], mare[]}
var per_rc := {}       # r*1000+c -> id
var fiumi := {}        # "A|B" ordinati -> true
var stretti := {}      # "A|B" -> true: esagoni di terra separati dal mare (si passa solo con le navi)
var vichy := []
var polonia_est := []
var griglie := {}
var forze := {}
var capitali := {}     # nazione -> esagono della capitale
var obiettivi := []    # esagoni obiettivo
var porti := {}        # id -> true
var industrie := []    # centri industriali sovietici

static func nome_riga(r: int) -> String:
	return LETTERE[r] if r < 26 else LETTERE[r - 26] + LETTERE[r - 26]

func carica() -> void:
	var f := FileAccess.open("res://assets/dati/mappa.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	for id in d["esagoni"]:
		var e: Array = d["esagoni"][id]
		var h := {"id": id, "r": int(e[0]), "c": int(e[1]), "t": int(e[2]), "n": str(e[3]), "citta": str(e[4]), "tipo": str(e[5])}
		esagoni[id] = h
		per_rc[int(e[0]) * 1000 + int(e[1])] = id
	for k in d["fiumi"]:
		var p: PackedStringArray = str(k).split(",")
		fiumi[_chiave(p[0], p[1])] = true
	for k in d.get("stretti", []):
		var p2: PackedStringArray = str(k).split(",")
		stretti[_chiave(p2[0], p2[1])] = true
	vichy = d["vichy"]
	polonia_est = d["polonia_est"]
	griglie = d["griglie"]
	var dirs := [[0, 1], [0, -1], [-1, 0], [-1, 1], [1, 0], [1, -1]]
	for id in esagoni:
		var h: Dictionary = esagoni[id]
		var v := []
		var vt := []
		for dd in dirs:
			var k: int = (h["r"] + dd[0]) * 1000 + h["c"] + dd[1]
			if per_rc.has(k):
				v.append(per_rc[k])
		h["vicini"] = v
	# vicini via terra: senza attraversare stretti di mare
	for id in esagoni:
		var h: Dictionary = esagoni[id]
		var vt := []
		for v in h["vicini"]:
			if not stretti.has(_chiave(id, v)):
				vt.append(v)
		h["terra"] = vt
	for id in esagoni:
		var h: Dictionary = esagoni[id]
		var costa := false
		if h["t"] != 9:
			for v in h["vicini"]:
				if esagoni[v]["t"] == 9:
					costa = true
		h["costa"] = costa
		var tipo: String = h["tipo"]
		if tipo.contains("C") and h["n"] != "":
			capitali[h["n"]] = id
		if tipo.contains("O"):
			obiettivi.append(id)
		if tipo.contains("P") and costa:
			porti[id] = true
		if tipo.contains("I"):
			industrie.append(id)
	# Vichy ha la sua capitale
	capitali["VIC"] = _cerca_citta("Vichy")
	var ff := FileAccess.open("res://assets/dati/forze.json", FileAccess.READ)
	forze = JSON.parse_string(ff.get_as_text())

func _cerca_citta(nome: String) -> String:
	for id in esagoni:
		if esagoni[id]["citta"] == nome:
			return id
	return ""

static func _chiave(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func fiume_tra(a: String, b: String) -> bool:
	return fiumi.has(_chiave(a, b))

func distanza(a: String, b: String) -> int:
	var ha: Dictionary = esagoni[a]
	var hb: Dictionary = esagoni[b]
	var dc: int = hb["c"] - ha["c"]
	var dr: int = hb["r"] - ha["r"]
	return maxi(maxi(absi(dc), absi(dr)), absi(dc + dr))

func terra(id: String) -> bool:
	return esagoni.has(id) and esagoni[id]["t"] != 9

## Posizione dell'esagono nell'immagine della mappa scelta, in frazioni (0..1)
func posizione(id: String, mappa: String) -> Vector2:
	var g: Dictionary = griglie[mappa]
	var h: Dictionary = esagoni[id]
	var x: float = g["x0"] + g["cx"] * h["c"] + g["rx"] * h["r"]
	var y: float = g["y0"] + g["ry"] * h["r"]
	return Vector2(x / g["img"][0], y / g["img"][1])

## Raggio dell'esagono (centro-vertice) in frazione della larghezza dell'immagine
func raggio(mappa: String) -> float:
	var g: Dictionary = griglie[mappa]
	return g["cx"] / sqrt(3.0) / g["img"][0]

static func lato_maggiore(n: String) -> String:
	return LATO_DI.get(n, "")

static func nome(n: String) -> String:
	return NOMI.get(n, n)

static func colonna_crt(att: float, dif: float) -> int:
	if dif <= 0.0:
		return 7
	if att >= dif:
		return mini(7, 2 + int(floor(att / dif)))
	var k := int(ceil(dif / att))
	if k > 4:
		return -1
	return 4 - k
