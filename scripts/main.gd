## Interfaccia del gioco: menu, tavolo 3D, pannello degli ordini, IA, salvataggi e gioco online.
extends Node

const VERSIONE := "1.0"

# colori del tema (carta delle tabelle della mappa, bordi rossi, verde oliva)
const C_CARTA := Color(0.93, 0.89, 0.8)
const C_CARTA_SCURA := Color(0.84, 0.78, 0.66)
const C_INCHIOSTRO := Color(0.11, 0.1, 0.09)
const C_ROSSO := Color(0.68, 0.13, 0.1)
const C_OLIVA := Color(0.29, 0.32, 0.2)
const C_NOTTE := Color(0.1, 0.09, 0.08, 0.92)
const COLORE_POTENZA := {"GER": Color(0.15, 0.15, 0.15), "ITA": Color(0.4, 0.72, 0.64), "GB": Color(0.86, 0.68, 0.4),
	"FRA": Color(0.43, 0.62, 0.84), "URSS": Color(0.85, 0.1, 0.06), "USA": Color(0.5, 0.62, 0.1)}

var D: Dati
var m: Motore
var ia: IA
var rete: Rete
var vista: Vista3D

var F_TITOLO: Font
var F_TESTO: Font
var F_GRASSETTO: Font
var F_CORSIVO: Font
var F_NUMERI: Font

var ui: CanvasLayer
var menu: Control
var barra: PanelContainer
var lab_data: Label
var lab_fase: Label
var box_brp: HBoxContainer
var pannello: PanelContainer
var contenuto: VBoxContainer
var lab_log: RichTextLabel
var info: PanelContainer
var lab_info: Label
var popup: Control
var toast: PanelContainer
var lab_toast: Label
var comandi: VBoxContainer

# configurazione della partita
var modo := "advanced"
var umani := {"asse": true, "alleati": false}
var livello := "normale"
var velocita := 1.0
var in_partita := false
var online := false
var mio_lato := ""
var codice := ""
var posto := -1
var n_applicate := 0
var _attesa_rete := 0.0
var _invio_in_corso := false

# selezioni dell'utente
var sel_unita := ""
var sel_esagono := ""
var attacco := {}
var costr := {}
var _avanza_scelte := {}
var _pausa := 0.0
var _rifiuti_ia := 0
var _salva_timer := 0.0
var _ultima_fase := ""
var _sopra := ""

func _ready() -> void:
	F_TITOLO = load("res://assets/font/BlackOpsOne-Regular.ttf")
	F_TESTO = load("res://assets/font/PTSerif.ttf")
	F_GRASSETTO = load("res://assets/font/PTSerifBold.ttf")
	F_CORSIVO = load("res://assets/font/PTSerifCorsivo.ttf")
	F_NUMERI = load("res://assets/font/Oswald.ttf")
	D = Dati.new()
	D.carica()
	rete = Rete.new()
	add_child(rete)
	vista = Vista3D.new()
	add_child(vista)
	vista.esagono_cliccato.connect(_clic_esagono)
	vista.esagono_sopra.connect(_sopra_esagono)
	vista.prepara(D, "advanced")
	ui = CanvasLayer.new()
	add_child(ui)
	_costruisci_ui()
	_mostra_menu()

# =====================================================================================
# Tema e mattoni dell'interfaccia
# =====================================================================================

func _stile(fondo: Color, bordo: Color, spessore := 2, raggio := 4, margine := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fondo
	s.border_color = bordo
	s.set_border_width_all(spessore)
	s.set_corner_radius_all(raggio)
	s.content_margin_left = margine
	s.content_margin_right = margine
	s.content_margin_top = margine * 0.7
	s.content_margin_bottom = margine * 0.7
	return s

func _tema() -> Theme:
	var t := Theme.new()
	t.default_font = F_TESTO
	t.default_font_size = 19
	t.set_color("font_color", "Label", C_INCHIOSTRO)
	t.set_stylebox("normal", "Button", _stile(C_OLIVA, Color(0.17, 0.19, 0.11), 2, 3, 12))
	t.set_stylebox("hover", "Button", _stile(C_OLIVA.lightened(0.15), Color(0.85, 0.75, 0.45), 2, 3, 12))
	t.set_stylebox("pressed", "Button", _stile(C_OLIVA.darkened(0.25), Color(0.85, 0.75, 0.45), 2, 3, 12))
	t.set_stylebox("disabled", "Button", _stile(Color(0.45, 0.43, 0.38), Color(0.35, 0.33, 0.3), 2, 3, 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.96, 0.93, 0.84))
	t.set_color("font_hover_color", "Button", Color(1, 0.97, 0.86))
	t.set_color("font_pressed_color", "Button", Color(1, 0.95, 0.8))
	t.set_color("font_disabled_color", "Button", Color(0.75, 0.73, 0.68))
	t.set_font("font", "Button", F_GRASSETTO)
	t.set_font_size("font_size", "Button", 18)
	t.set_color("font_color", "CheckBox", C_INCHIOSTRO)
	t.set_color("font_hover_color", "CheckBox", C_ROSSO)
	t.set_color("font_pressed_color", "CheckBox", C_INCHIOSTRO)
	t.set_color("font_hover_pressed_color", "CheckBox", C_ROSSO)
	t.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", _stile(Color(1, 0.98, 0.92), C_ROSSO, 2, 3, 8))
	t.set_stylebox("focus", "LineEdit", _stile(Color(1, 0.98, 0.92), C_ROSSO.lightened(0.2), 2, 3, 8))
	t.set_color("font_color", "LineEdit", C_INCHIOSTRO)
	t.set_stylebox("panel", "PanelContainer", _stile(C_CARTA, C_ROSSO, 3, 4, 12))
	t.set_stylebox("panel", "TooltipPanel", _stile(C_CARTA, C_ROSSO, 2, 3, 8))
	t.set_color("font_color", "TooltipLabel", C_INCHIOSTRO)
	t.set_font("font", "TooltipLabel", F_TESTO)
	t.set_color("default_color", "RichTextLabel", C_INCHIOSTRO)
	t.set_font("normal_font", "RichTextLabel", F_TESTO)
	t.set_font("bold_font", "RichTextLabel", F_GRASSETTO)
	t.set_font("italics_font", "RichTextLabel", F_CORSIVO)
	t.set_font_size("normal_font_size", "RichTextLabel", 16)
	t.set_font_size("bold_font_size", "RichTextLabel", 16)
	t.set_font_size("italics_font_size", "RichTextLabel", 16)
	return t

func _etichetta(testo: String, dim := 19, font: Font = null, colore := C_INCHIOSTRO) -> Label:
	var l := Label.new()
	l.text = testo
	l.add_theme_font_size_override("font_size", dim)
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", colore)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func titolo(testo: String, dim := 24, colore := C_ROSSO) -> Label:
	var l := _etichetta(testo, dim, F_TITOLO, colore)
	return l

func _bottone(testo: String, azione: Callable, abilitato := true) -> Button:
	var b := Button.new()
	b.text = testo
	b.disabled = not abilitato
	b.pressed.connect(azione)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# larghezza minima pari alla parola più lunga: il testo va a capo tra le parole, mai lettera per lettera
	var largo := 0.0
	if F_TESTO != null:
		for parola in testo.split(" ", false):
			largo = maxf(largo, F_TESTO.get_string_size(parola, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x)
	b.custom_minimum_size = Vector2(minf(largo + 34.0, 360.0), 44)
	return b

func _separatore() -> HSeparator:
	var s := HSeparator.new()
	var st := StyleBoxLine.new()
	st.color = Color(C_ROSSO, 0.6)
	st.thickness = 2
	s.add_theme_stylebox_override("separator", st)
	return s

func _costruisci_ui() -> void:
	var radice := Control.new()
	radice.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radice.theme = _tema()
	ui.add_child(radice)
	# barra in alto
	barra = PanelContainer.new()
	barra.add_theme_stylebox_override("panel", _stile(C_NOTTE, C_ROSSO, 0, 0, 12))
	barra.set_anchors_preset(Control.PRESET_TOP_WIDE)
	barra.offset_bottom = 66
	radice.add_child(barra)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	barra.add_child(hb)
	var t := titolo("THIRD REICH", 30, Color(0.86, 0.2, 0.14))
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(t)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", -4)
	hb.add_child(dv)
	lab_data = _etichetta("", 22, F_GRASSETTO, Color(0.95, 0.9, 0.78))
	lab_data.autowrap_mode = TextServer.AUTOWRAP_OFF
	dv.add_child(lab_data)
	lab_fase = _etichetta("", 16, F_CORSIVO, Color(0.85, 0.8, 0.68))
	lab_fase.autowrap_mode = TextServer.AUTOWRAP_OFF
	dv.add_child(lab_fase)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	box_brp = HBoxContainer.new()
	box_brp.add_theme_constant_override("separation", 14)
	hb.add_child(box_brp)
	var bm := _bottone("Menu", _apri_menu_partita)
	bm.custom_minimum_size = Vector2(90, 40)
	hb.add_child(bm)
	# pannello degli ordini a destra
	pannello = PanelContainer.new()
	pannello.anchor_left = 1.0
	pannello.anchor_right = 1.0
	pannello.anchor_bottom = 1.0
	pannello.offset_left = -410
	pannello.offset_right = -10
	pannello.offset_top = 76
	pannello.offset_bottom = -10
	radice.add_child(pannello)
	# il pannello laterale contiene: ordini della fase, esagono sotto il puntatore e registro
	var colonna := VBoxContainer.new()
	colonna.add_theme_constant_override("separation", 6)
	pannello.add_child(colonna)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	colonna.add_child(sc)
	contenuto = VBoxContainer.new()
	contenuto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contenuto.add_theme_constant_override("separation", 8)
	sc.add_child(contenuto)
	# esagono sotto il puntatore (sostituisce il riquadro che compariva sulla mappa)
	info = PanelContainer.new()
	info.add_theme_stylebox_override("panel", _stile(Color(0.88, 0.83, 0.72, 1.0), Color(0.55, 0.45, 0.35), 1, 3, 6))
	info.custom_minimum_size = Vector2(0, 96)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	colonna.add_child(info)
	lab_info = _etichetta("Passa sopra un esagono per vederne i dettagli.", 14, F_CORSIVO, Color(0.35, 0.3, 0.25))
	lab_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(lab_info)
	# registro degli eventi
	var pl := PanelContainer.new()
	pl.add_theme_stylebox_override("panel", _stile(Color(0.93, 0.89, 0.8, 1.0), C_ROSSO, 2, 4, 6))
	pl.custom_minimum_size = Vector2(0, 230)
	colonna.add_child(pl)
	lab_log = RichTextLabel.new()
	lab_log.bbcode_enabled = true
	lab_log.scroll_following = true
	lab_log.add_theme_font_size_override("normal_font_size", 13)
	lab_log.add_theme_font_size_override("bold_font_size", 14)
	pl.add_child(lab_log)
	# comandi della telecamera
	comandi = VBoxContainer.new()
	comandi.anchor_left = 1.0
	comandi.anchor_right = 1.0
	comandi.anchor_top = 1.0
	comandi.anchor_bottom = 1.0
	comandi.offset_left = -540
	comandi.offset_right = -425
	comandi.offset_top = -250
	comandi.offset_bottom = -10
	comandi.add_theme_constant_override("separation", 6)
	radice.add_child(comandi)
	for c in [["Zoom +", func(): vista.zoom(0.8)], ["Zoom -", func(): vista.zoom(1.25)], ["Dall'alto", func(): vista.vista_dall_alto()], ["Inclinata", func(): vista.vista_inclinata()]]:
		var b := _bottone(c[0], c[1])
		b.custom_minimum_size = Vector2(110, 40)
		b.add_theme_font_size_override("font_size", 15)
		comandi.add_child(b)
	# avviso temporaneo (esiti dei combattimenti)
	toast = PanelContainer.new()
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.offset_left = -330
	toast.offset_right = 330
	toast.offset_top = 80
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radice.add_child(toast)
	lab_toast = _etichetta("", 18, F_GRASSETTO)
	lab_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(lab_toast)
	toast.visible = false
	# popup modale
	popup = Control.new()
	popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.visible = false
	radice.add_child(popup)
	# menu principale
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.add_child(menu)

func _mostra_ui_partita(v: bool) -> void:
	barra.visible = v
	pannello.visible = v
	comandi.visible = v
	pass

# =====================================================================================
# Menu
# =====================================================================================

func _mostra_menu() -> void:
	in_partita = false
	_mostra_ui_partita(false)
	for c in menu.get_children():
		c.queue_free()
	menu.visible = true
	var fondo := ColorRect.new()
	fondo.color = Color(0.05, 0.045, 0.04, 0.55)
	fondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(fondo)
	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(centro)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 0)
	centro.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var t := titolo("THIRD REICH", 64, C_ROSSO)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := _etichetta("La seconda guerra mondiale in Europa, 1939-1945", 22, F_CORSIVO)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	v.add_child(_separatore())
	# versione del regolamento
	v.add_child(_etichetta("Versione del gioco", 20, F_GRASSETTO))
	var hv := HBoxContainer.new()
	hv.add_theme_constant_override("separation", 10)
	v.add_child(hv)
	var gruppo := ButtonGroup.new()
	for x in [["base", "Rise and Decline (base)"], ["advanced", "Advanced Third Reich"]]:
		var b := CheckBox.new()
		b.text = x[1]
		b.button_group = gruppo
		b.button_pressed = modo == x[0]
		b.add_theme_font_override("font", F_GRASSETTO)
		var val: String = x[0]
		b.toggled.connect(func(on): if on: _cambia_modo(val))
		hv.add_child(b)
	var spieg := _etichetta(_spiega_modo(), 16, F_CORSIVO)
	spieg.name = "Spiega"
	v.add_child(spieg)
	v.add_child(_separatore())
	v.add_child(_etichetta("Partita su questo dispositivo", 20, F_GRASSETTO))
	var hg := GridContainer.new()
	hg.columns = 2
	hg.add_theme_constant_override("h_separation", 10)
	hg.add_theme_constant_override("v_separation", 10)
	v.add_child(hg)
	for x in [["Gioca l'Asse contro l'IA", {"asse": true, "alleati": false}], ["Gioca gli Alleati contro l'IA", {"asse": false, "alleati": true}],
			["Due giocatori sullo stesso schermo", {"asse": true, "alleati": true}], ["Guarda l'IA contro l'IA", {"asse": false, "alleati": false}]]:
		var u: Dictionary = x[1]
		var b := _bottone(x[0], func(): _nuova_partita(u))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hg.add_child(b)
	var hl := HBoxContainer.new()
	hl.add_theme_constant_override("separation", 10)
	v.add_child(hl)
	var lia := _etichetta("Livello dell'IA:", 18, F_GRASSETTO)
	lia.autowrap_mode = TextServer.AUTOWRAP_OFF
	hl.add_child(lia)
	var gl := ButtonGroup.new()
	for x in [["normale", "normale"], ["esperta", "esperta (+20% BRP)"]]:
		var b := CheckBox.new()
		b.text = x[1]
		b.button_group = gl
		b.button_pressed = livello == x[0]
		var val: String = x[0]
		b.toggled.connect(func(on): if on: livello = val)
		hl.add_child(b)
	v.add_child(_separatore())
	var hc := HBoxContainer.new()
	hc.add_theme_constant_override("separation", 10)
	v.add_child(hc)
	var bc := _bottone("Continua la partita salvata", _continua)
	bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_child(bc)
	var bo := _bottone("Gioco online", _menu_online)
	bo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_child(bo)
	var br := _bottone("Regole", _mostra_regole)
	br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hc.add_child(br)
	var nota := _etichetta("Versione digitale per uso personale. Mappe e pedine dai moduli originali; regole adattate al computer.", 14, F_CORSIVO, Color(0.35, 0.32, 0.28))
	nota.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nota)

func _spiega_modo() -> String:
	if modo == "base":
		return "Regolamento classico: le potenze minori dell'Asse entrano in guerra con l'attacco all'URSS, nessuna diplomazia."
	return "Aggiunge diplomazia annuale, inverno russo, petrolio di Ploesti, guerra sottomarina e strategica, affitti e prestiti all'URSS."

func _cambia_modo(x: String) -> void:
	modo = x
	vista.prepara(D, modo)
	var s := menu.find_child("Spiega", true, false)
	if s:
		s.text = _spiega_modo()

func _mostra_regole() -> void:
	var testo := """[b]Scopo.[/b] L'Asse (Germania e Italia) cerca di conquistare l'Europa; gli Alleati (Gran Bretagna, Francia, Unione Sovietica e dall'inverno 1941 Stati Uniti) devono fermarlo. La partita finisce con la resa della Germania o della Gran Bretagna, oppure all'estate 1945: si contano allora gli esagoni obiettivo (le città con il cartiglio rosso) controllati dall'Asse.

[b]Turno.[/b] Ogni stagione muove prima uno schieramento e poi l'altro. Fasi: dichiarazioni di guerra, scelta delle opzioni, movimento, combattimento, sfruttamento degli sfondamenti, costruzione, ridispiegamento strategico.

[b]BRP.[/b] Sono la ricchezza delle potenze. Si spendono per dichiarare guerra (35 a una potenza maggiore, 10 a un paese minore), per l'offensiva (15) e per costruire unità (fanteria e rimpiazzi 1 per fattore, corazzati 2, aviotrasportati, flotte e aviazione 3). In primavera i BRP non spesi fanno crescere la base; contano anche i paesi conquistati e le colonie.

[b]Opzioni.[/b] Offensiva: si può attaccare e sfondare. Logoramento: gratis, si tira sulla tabella del logoramento con i fattori a contatto del nemico. Passo: niente combattimenti. Nel 1939 Francia e Gran Bretagna non possono scegliere l'offensiva; fino al 1941 britannici e francesi non attaccano insieme e il corpo di spedizione britannico sul continente ha al massimo 4 unità.

[b]Movimento.[/b] Pianura 1, montagna e palude 2. Entrando in una zona di controllo nemica (esagoni adiacenti a unità nemiche) ci si ferma. Al massimo 2 unità terrestri per esagono. Le unità in un porto con flotte sufficienti possono sbarcare su una costa raggiungibile per mare. L'aviazione si sposta fino a 8 esagoni.

[b]Combattimento.[/b] Si attacca un esagono nemico adiacente; l'aviazione entro 4 esagoni aggiunge i suoi fattori (anche in difesa). Montagne, paludi e fiumi (se tutti gli attaccanti li attraversano) raddoppiano la difesa. Tabella: D difensore eliminato, A attaccante eliminato, Ex scambio, CA contrattacco del difensore. Se i corazzati vincono e avanzano si apre uno sfondamento: possono muovere ancora e attaccare di nuovo, anche insieme alle unità che in questo turno non hanno ancora attaccato.

[b]Rifornimenti.[/b] Le unità devono collegarsi via terra a città della patria, capitali o porti amici. Le unità isolate per due turni consecutivi sono eliminate.

[b]Conquiste.[/b] Un paese cade quando il nemico ne prende la capitale; la Francia si arrende appena le truppe dell'Asse occupano Parigi alla fine del turno dell'Asse. La Francia arresa lascia la Francia di Vichy, neutrale. L'Italia si arrende se cade Roma, l'URSS se cadono Mosca e due fra Leningrado, Stalingrado, Kharkov e Kiev.

[b]Advanced.[/b] In primavera ogni schieramento distribuisce i punti diplomatici sui paesi neutrali (2 dadi più la differenza dei punti: con risultati alti il paese si schiera con l'Asse, con risultati bassi, dal 1942, con gli Alleati). Inverno russo, perdita di BRP senza Ploesti, sommergibili e bombardamenti, aiuti americani all'URSS.

[b]Comandi.[/b] Clic su un'unità per selezionarla, clic su un esagono evidenziato per muovere. Trascina per spostare la mappa, rotella o pizzico per lo zoom, tasto destro o due dita per ruotare e inclinare."""
	_apri_popup("Regole", testo, [["Chiudi", _chiudi_popup]])

# =====================================================================================
# Avvio e salvataggi
# =====================================================================================

func _nuova_partita(u: Dictionary) -> void:
	umani = u
	online = false
	m = Motore.new(D)
	m.nuova(modo, int(Time.get_unix_time_from_system()) % 1000000 + randi() % 1000)
	_imposta_livello()
	_avvia()

func _imposta_livello() -> void:
	m.s["livello"] = livello
	m.s["umani"] = umani

func _avvia() -> void:
	ia = IA.new(m)
	m.evento.connect(_al_evento)
	modo = m.s["modo"]
	vista.prepara(D, modo)
	menu.visible = false
	in_partita = true
	_mostra_ui_partita(true)
	sel_unita = ""
	attacco = {}
	costr = {}
	vista.aggiorna(m.s, false)
	var cap := "M30"
	vista.bersaglio = vista.mondo(cap)
	lab_log.clear()
	for l in m.s["log"].slice(maxi(0, m.s["log"].size() - 30)):
		_scrivi_log(l)
	_aggiorna()

func _al_evento(t: String) -> void:
	_scrivi_log(t)
	# bonus BRP dell'IA esperta all'inizio dell'anno
	if t.begins_with("Inizio anno") and m.s.get("livello", "normale") == "esperta" and not online:
		for p in Dati.MAGGIORI:
			var l := m.lato(p)
			if not m.s.get("umani", umani).get(l, false) and not m.s["pot"][p]["arresa"]:
				m.s["pot"][p]["brp"] = int(m.s["pot"][p]["brp"] * 1.2)

func _scrivi_log(t: String) -> void:
	if t.begins_with("—"):
		lab_log.append_text("\n[b]%s[/b]\n" % t.replace("[", "(").replace("]", ")"))
	else:
		lab_log.append_text(t.replace("[", "(").replace("]", ")") + "\n")

const FILE_LOCALE := "user://partita_terzoreich.json"

func _salva() -> void:
	if online or m == null:
		return
	var st := m.esporta()
	st["umani"] = umani
	var f := FileAccess.open(FILE_LOCALE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(st))
		f.close()
	rete.salva_partita(st)

func _continua() -> void:
	_messaggio("Caricamento della partita salvata...")
	var st := await rete.carica_partita()
	if st.is_empty():
		var f := FileAccess.open(FILE_LOCALE, FileAccess.READ)
		if f:
			var x = JSON.parse_string(f.get_as_text())
			if x is Dictionary:
				st = x
	_chiudi_popup()
	if st.is_empty() or not st.has("pot"):
		_apri_popup("Nessuna partita salvata", "Non ho trovato partite salvate né online né su questo dispositivo.", [["Chiudi", _chiudi_popup]])
		return
	m = Motore.new(D)
	m.importa(st)
	umani = st.get("umani", {"asse": true, "alleati": false})
	online = false
	_avvia()

func _apri_menu_partita() -> void:
	var bott := [["Riprendi", _chiudi_popup]]
	if not online:
		bott.append(["Salva ora", func(): _salva(); _chiudi_popup(); _mostra_toast("Partita salvata.")])
	bott.append(["Regole", func(): _chiudi_popup(); _mostra_regole()])
	bott.append(["Velocità IA: " + ("rapida" if velocita < 1.0 else "normale"), func(): velocita = 0.3 if velocita >= 1.0 else 1.0; _chiudi_popup()])
	bott.append(["Torna al menu", func(): _salva(); _chiudi_popup(); _mostra_menu()])
	_apri_popup("Menu", "%s, %s." % [m.data_testo(), "versione Advanced" if m.advanced() else "versione base"], bott)

# =====================================================================================
# Popup e avvisi
# =====================================================================================

func _apri_popup(t: String, testo: String, bottoni: Array) -> void:
	for c in popup.get_children():
		c.queue_free()
	popup.visible = true
	var f := ColorRect.new()
	f.color = Color(0, 0, 0, 0.45)
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(f)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(cc)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(700, 0)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(titolo(t.to_upper(), 26))
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.custom_minimum_size = Vector2(660, 0)
	r.add_theme_font_size_override("normal_font_size", 18)
	r.add_theme_font_size_override("bold_font_size", 18)
	r.text = testo
	if testo.length() > 900:
		r.fit_content = false
		r.custom_minimum_size = Vector2(660, 560)
	v.add_child(r)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	if bottoni.size() > 3:
		h.queue_free()
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 10)
		g.add_theme_constant_override("v_separation", 10)
		v.add_child(g)
		for b in bottoni:
			var bt := _bottone(b[0], b[1])
			bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.add_child(bt)
		return
	for b in bottoni:
		h.add_child(_bottone(b[0], b[1]))

func _messaggio(t: String) -> void:
	_apri_popup("Attendere", t, [])

func _chiudi_popup() -> void:
	popup.visible = false
	for c in popup.get_children():
		c.queue_free()

var _toast_tempo := 0.0

func _mostra_toast(t: String, durata := 3.5) -> void:
	lab_toast.text = t
	toast.visible = true
	_toast_tempo = durata

# =====================================================================================
# Ciclo: IA, rete, salvataggi
# =====================================================================================

func _process(delta: float) -> void:
	if _toast_tempo > 0:
		_toast_tempo -= delta
		if _toast_tempo <= 0:
			toast.visible = false
	if not in_partita or m == null:
		return
	if online:
		_ciclo_online(delta)
		return
	if _salva_timer > 0:
		_salva_timer -= delta
		if _salva_timer <= 0:
			_salva()
	if popup.visible or m.finita():
		return
	if _pausa > 0:
		_pausa -= delta
		return
	var r := m.richiesta()
	if r["k"] == "fine":
		return
	if umani.get(r["g"], false):
		return
	_passo_ia(r)

func _passo_ia(r: Dictionary) -> void:
	var d := ia.decidi(r)
	var prima := _prima_di_applicare(d)
	var res := m.applica(d)
	if not res["ok"]:
		_rifiuti_ia += 1
		if _rifiuti_ia > 20:
			m.applica({"t": "fine"})
			_rifiuti_ia = 0
		return
	_rifiuti_ia = 0
	_dopo_decisione(d, res, prima)
	var t: String = d.get("t", "")
	match t:
		"muovi", "sr":
			_pausa = 0.18 * velocita
		"attacca":
			_pausa = 1.2 * velocita
		"fine":
			_pausa = 0.35 * velocita
		_:
			_pausa = 0.25 * velocita

## dopo ogni decisione (umana, IA o arrivata dalla rete)
## posizioni da ricordare prima che una decisione sposti le pedine (per le frecce)
func _prima_di_applicare(d: Dictionary) -> Dictionary:
	var out := {}
	if m == null:
		return out
	match d.get("t", ""):
		"avanza":
			var da := []
			for uid in d.get("u", []):
				if m.s["u"].has(uid):
					da.append(m.s["u"][uid]["h"])
			out["da"] = da
		"muovi":
			var uid: String = d.get("u", "")
			if m.s["u"].has(uid):
				out["da"] = m.s["u"][uid]["h"]
				out["tipo"] = m.s["u"][uid]["t"]
				var sf: bool = m.s["fase"] == "sfruttamento"
				out["mare"] = Motore._terrestre(m.s["u"][uid]["t"]) and int(m.raggiungibili(uid, sf).get(d.get("h", ""), 0)) == -1
	return out

const COL_ASSE := Color(0.85, 0.12, 0.08, 0.95)
const COL_ALLEATI := Color(0.2, 0.45, 0.95, 0.95)

func _frecce_decisione(d: Dictionary, res: Dictionary, prima: Dictionary) -> void:
	var t: String = d.get("t", "")
	if t == "attacca" and res.has("risultato"):
		var r: Dictionary = res["risultato"]
		var col := COL_ASSE if r.get("lato", "") == "asse" else COL_ALLEATI
		var b: String = r["bersaglio"]
		var visti := {}
		for h in r.get("da", []):
			if not visti.has(h):
				visti[h] = true
				vista.freccia(h, b, col, 1.0)
		# appoggio aereo: archi tratteggiati gialli (attacco) e bianchi (difesa)
		for h in r.get("aerei_h", []):
			vista.freccia(h, b, Color(1.0, 0.85, 0.15, 0.95), 0.7, 1.2, 0.0, true)
		for h in r.get("aerei_dif_h", []):
			vista.freccia(h, b, Color(0.95, 0.95, 0.95, 0.9), 0.6, 1.0, 0.0, true)
	elif t == "avanza":
		var h: String = m.s["avanzata"].get("h", "") if m.s["avanzata"].has("h") else ""
		for da in prima.get("da", []):
			var dest := ""
			for uid in d.get("u", []):
				if m.s["u"].has(uid):
					dest = m.s["u"][uid]["h"]
			vista.freccia(da, dest if dest != "" else h, Color(0.35, 0.85, 0.3, 0.95), 0.8)
			break
	elif t == "muovi" and prima.get("mare", false):
		# sbarco anfibio: rotta navale curva in azzurro con il segno dell'ancora sul porto di partenza
		_freccia_mare(prima["da"], d.get("h", ""), Color(0.1, 0.85, 0.95, 0.95), 1.1)
		vista.segno(prima["da"], Color(0.1, 0.85, 0.95, 1.0))
	elif t == "muovi" and prima.get("tipo", "") == "flo":
		_freccia_mare(prima["da"], d.get("h", ""), Color(0.55, 0.75, 0.95, 0.8), 0.6)
	elif t == "muovi" and prima.get("tipo", "") == "avi":
		vista.freccia(prima["da"], d.get("h", ""), Color(1.0, 0.85, 0.15, 0.7), 0.5, 0.8, 0.0, true)

## freccia lungo la rotta navale (se trovata), altrimenti una curva diretta
func _freccia_mare(da: String, a: String, col: Color, spessore: float) -> void:
	var rotta: Array = vista.rotta_mare(da, a) if da != "USA" else []
	if rotta.size() > 0:
		vista.freccia_percorso([da] + rotta + [a], col, spessore, true)
	else:
		vista.freccia(da, a, col, spessore, 0.0, 0.18, true)

func _dopo_decisione(d: Dictionary, res: Dictionary, prima := {}) -> void:
	var t: String = d.get("t", "")
	vista.tempo_anim = 0.18 * velocita if not umani.get(m.s["lato"], false) else 0.22
	vista.aggiorna(m.s, true)
	if res.get("ok", false):
		_frecce_decisione(d, res, prima)
	if t == "attacca" and res.has("risultato"):
		var r: Dictionary = res["risultato"]
		var testo: String = r.get("testo", "")
		# l'esito appare sulla mappa solo per gli attacchi del giocatore: quelli dell'IA vanno nel registro
		if umani.get(m.s["lato"], false):
			_mostra_toast(testo, 4.5)
		vista.evidenzia("ultimo", [r["bersaglio"]])
	elif t in ["muovi", "sr"]:
		vista.evidenzia("ultimo", [d.get("h", "")])
	if m.s["fase"] != _ultima_fase:
		# le frecce di un turno (sbarchi, attacchi, avanzate) restano visibili fino al movimento successivo
		if m.s["fase"] == "movimento":
			vista.pulisci_frecce()
		_ultima_fase = m.s["fase"]
		_salva_timer = 1.0
		vista.evidenzia("ultimo", [])
	if m.finita():
		_salva_timer = 0.5
		_fine_partita()
	_aggiorna()

func _fine_partita() -> void:
	_apri_popup("Fine della guerra", "[b]%s[/b]\n\nEsagoni obiettivo controllati dall'Asse: %d su %d." % [m.s["fine"], m.obiettivi_asse(), D.obiettivi.size()],
		[["Guarda la mappa", _chiudi_popup], ["Menu", func(): _chiudi_popup(); _mostra_menu()]])

# =====================================================================================
# Decisioni dell'utente
# =====================================================================================

func _mio_turno() -> bool:
	if m == null or m.finita():
		return false
	var r := m.richiesta()
	if online:
		return r["g"] == mio_lato and not _invio_in_corso
	return umani.get(r["g"], false)

func _decidi(d: Dictionary) -> Dictionary:
	if online:
		return await _decidi_online(d)
	var prima := _prima_di_applicare(d)
	var res := m.applica(d)
	if not res["ok"]:
		_mostra_toast(res.get("msg", "non valido"), 2.5)
		return res
	_dopo_decisione(d, res, prima)
	return res

func _clic_esagono(id: String) -> void:
	if not in_partita or popup.visible or not _mio_turno():
		_seleziona_info(id)
		return
	var r := m.richiesta()
	match r["k"]:
		"movimento", "sfruttamento":
			_clic_movimento(id, r["k"] == "sfruttamento")
		"combattimento":
			_clic_combattimento(id, false)
		"costruzione":
			if not costr.is_empty():
				if m.luoghi_costruzione(costr["p"], costr["t"]).has(id):
					var i := _indice_pool(costr["p"], costr["e"])
					if i >= 0:
						await _decidi({"t": "costruisci", "p": costr["p"], "i": i, "h": id})
					costr = {}
					_aggiorna()
					return
			_seleziona_info(id)
		"ridispiegamento":
			_clic_sr(id)
		_:
			_seleziona_info(id)

func _seleziona_info(id: String) -> void:
	sel_esagono = id
	_aggiorna()

func _clic_movimento(id: String, sfr: bool) -> void:
	if sel_unita != "" and m.s["u"].has(sel_unita):
		var rr := m.raggiungibili(sel_unita, sfr)
		if rr.has(id):
			var uid := sel_unita
			sel_unita = ""
			await _decidi({"t": "muovi", "u": uid, "h": id})
			# resta selezionata la prossima unità della stessa pila
			_seleziona_prima_mobile(m.s["u"].get(uid, {}).get("h", ""), sfr, uid)
			_aggiorna()
			return
	if sfr:
		var att := m.attaccanti_possibili(id, true)
		if att.size() > 0:
			_prepara_attacco(id, true)
			return
	sel_esagono = id
	_seleziona_prima_mobile(id, sfr)
	_aggiorna()

func _seleziona_prima_mobile(id: String, sfr: bool, escludi := "") -> void:
	sel_unita = ""
	if id == "":
		return
	var lista := m.unita_in(id)
	lista.sort_custom(func(a, b): return Motore._terrestre(m.s["u"][a]["t"]) and not Motore._terrestre(m.s["u"][b]["t"]))
	for uid in lista:
		if uid != escludi and m.puo_muovere(uid, sfr) and m.raggiungibili(uid, sfr).size() > 0:
			sel_unita = uid
			return

func _clic_combattimento(id: String, sfr: bool) -> void:
	var att := m.attaccanti_possibili(id, sfr)
	if att.is_empty():
		attacco = {}
		sel_esagono = id
		_aggiorna()
		return
	_prepara_attacco(id, sfr)

func _prepara_attacco(id: String, sfr: bool) -> void:
	var att := m.attaccanti_possibili(id, sfr)
	if not m.cooperazione_ok(att):
		# sceglie la nazione più forte; l'utente può cambiare
		var gb := []
		for uid in att:
			if m.comandante(m.s["u"][uid]["n"]) == "GB":
				gb.append(uid)
		var resto := []
		for uid in att:
			if not gb.has(uid):
				resto.append(uid)
		att = gb if gb.size() >= resto.size() else resto
	attacco = {"h": id, "u": att, "av": [], "sf": sfr}
	sel_esagono = id
	_aggiorna()

func _clic_sr(id: String) -> void:
	if sel_unita != "" and m.destinazioni_sr(sel_unita).has(id):
		var uid := sel_unita
		sel_unita = ""
		await _decidi({"t": "sr", "u": uid, "h": id})
		_aggiorna()
		return
	sel_unita = ""
	sel_esagono = id
	for uid in m.unita_in(id):
		if m.destinazioni_sr(uid).size() > 0:
			sel_unita = uid
			break
	_aggiorna()

func _indice_pool(p: String, e: Array) -> int:
	var pool: Array = m.s["pool"][p]
	for i in pool.size():
		if str(pool[i][0]) == str(e[0]) and int(pool[i][1]) == int(e[1]) and int(pool[i][2]) == int(e[2]):
			return i
	return -1

func _sopra_esagono(id: String) -> void:
	_sopra = id
	if m == null or not in_partita:
		return
	if id == "":
		id = sel_esagono
	if id == "":
		return
	lab_info.text = _testo_esagono(id)
	lab_info.add_theme_color_override("font_color", Color(0.15, 0.12, 0.1))
	lab_info.add_theme_font_override("font", F_TESTO)

func _testo_esagono(id: String) -> String:
	if id == "USA":
		var n := m.unita_in("USA").size()
		return "Stati Uniti: %d unità in attesa di imbarco." % n
	var h: Dictionary = D.esagoni[id]
	var righe := []
	var testa := id
	if h["citta"] != "":
		testa = "%s (%s)" % [h["citta"], id]
	righe.append(testa)
	var extra := []
	extra.append(Dati.TERRENO[int(h["t"])] if int(h["t"]) != 9 else "mare")
	var tipo: String = h["tipo"]
	if tipo.contains("C"):
		extra.append("capitale")
	if tipo.contains("O"):
		extra.append("obiettivo")
	if D.porti.has(id):
		extra.append("porto")
	if tipo.contains("I"):
		extra.append("industria")
	righe.append(", ".join(extra))
	var c := m.controllo(id)
	if c != "":
		righe.append("Controllo: %s" % Dati.nome(c))
	for uid in m.unita_in(id):
		righe.append("- " + m.descrizione_unita(uid) + (" (senza rifornimenti)" if int(m.s["u"][uid]["nr"]) > 0 else ""))
	return "\n".join(righe)

# =====================================================================================
# Aggiornamento dell'interfaccia
# =====================================================================================

func _aggiorna() -> void:
	if m == null:
		return
	var r := m.richiesta()
	lab_data.text = "%s  -  turno %d" % [m.data_testo(), int(m.s["turno"])]
	var chi := "Asse" if m.s["lato"] == "asse" else "Alleati"
	var fase: String = Motore.NOMI_FASE.get(r["k"], r["k"])
	lab_fase.text = "Muovono: %s  -  %s%s" % [chi, fase, "  (Advanced)" if m.advanced() else ""]
	for c in box_brp.get_children():
		c.queue_free()
	for p in Dati.MAGGIORI:
		var pot: Dictionary = m.s["pot"][p]
		var chip := PanelContainer.new()
		var col: Color = COLORE_POTENZA[p]
		chip.add_theme_stylebox_override("panel", _stile(Color(0.16, 0.15, 0.13), col if p != "GER" else Color(0.6, 0.6, 0.6), 2, 3, 6))
		var l := _etichetta("%s %s" % [_sigla(p), "resa" if pot["arresa"] else str(pot["brp"])], 16, F_NUMERI, Color(0.95, 0.9, 0.78))
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.tooltip_text = "%s: BRP disponibili %d, base %d%s" % [Dati.nome(p), pot["brp"], pot["base"], "" if m.attiva(p) else " (non in guerra)"]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(l)
		box_brp.add_child(chip)
	_aggiorna_pannello(r)
	_aggiorna_evidenze(r)

func _sigla(p: String) -> String:
	return {"GER": "GER", "ITA": "ITA", "GB": "GB", "FRA": "FRA", "URSS": "URSS", "USA": "USA"}[p]

func _pulisci_pannello() -> void:
	for c in contenuto.get_children():
		c.queue_free()

func _aggiorna_pannello(r: Dictionary) -> void:
	_pulisci_pannello()
	var k: String = r["k"]
	contenuto.add_child(titolo(Motore.NOMI_FASE.get(k, k).to_upper(), 22))
	if k == "fine":
		contenuto.add_child(_etichetta(m.s["fine"], 19, F_GRASSETTO))
		contenuto.add_child(_bottone("Menu principale", _mostra_menu))
		return
	var mio := _mio_turno()
	if not mio:
		var chi := "l'Asse" if r["g"] == "asse" else "gli Alleati"
		if online:
			contenuto.add_child(_etichetta("Tocca all'avversario (%s). Attendere..." % chi, 19, F_CORSIVO))
		else:
			contenuto.add_child(_etichetta("L'IA sta giocando per %s..." % chi, 19, F_CORSIVO))
		_info_selezione()
		return
	match k:
		"diplomazia":
			_pannello_diplomazia(r)
		"dichiarazioni":
			_pannello_dichiarazioni()
		"opzioni":
			_pannello_opzioni(r)
		"movimento":
			_pannello_movimento(false)
		"sfruttamento":
			_pannello_movimento(true)
		"combattimento":
			_pannello_combattimento()
		"avanzata":
			_pannello_avanzata(r)
		"costruzione":
			_pannello_costruzione()
		"ridispiegamento":
			_pannello_sr()

func _info_selezione() -> void:
	# l'esagono selezionato compare nel riquadro informativo del pannello
	if sel_esagono != "":
		_sopra_esagono(sel_esagono)

func _spiega(t: String) -> void:
	contenuto.add_child(_etichetta(t, 16, F_CORSIVO, Color(0.3, 0.27, 0.23)))

func _pannello_diplomazia(r: Dictionary) -> void:
	_spiega("Distribuisci i punti diplomatici sui paesi neutrali. In primavera si tira per ognuno: 2 dadi più i punti dell'Asse meno quelli degli Alleati.")
	contenuto.add_child(_etichetta("Punti da assegnare: %d" % int(r["dp"]), 20, F_GRASSETTO))
	var dp: Dictionary = m.s.get("dp", {})
	for c in r["bersagli"]:
		var h := HBoxContainer.new()
		var a := int(dp.get(c, {}).get("asse", 0))
		var b := int(dp.get(c, {}).get("alleati", 0))
		var l := _etichetta("%s  (Asse %d, Alleati %d)" % [Dati.nome(c), a, b], 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var cc: String = c
		h.add_child(_bottone("+1", func(): await _decidi({"t": "dp", "c": cc}), int(r["dp"]) > 0))
		contenuto.add_child(h)
	contenuto.add_child(_bottone("Fatto", func(): await _decidi({"t": "fine"})))

func _pannello_dichiarazioni() -> void:
	_spiega("Puoi dichiarare guerra prima di scegliere le opzioni: 35 BRP contro una potenza maggiore, 10 contro un paese minore.")
	var qualcuna := false
	for p in m.potenze_del_lato(m.s["lato"]):
		var poss := m.dichiarazioni_possibili(p)
		if poss.is_empty():
			continue
		qualcuna = true
		contenuto.add_child(_etichetta("%s (BRP %d)" % [Dati.nome(p), m.s["pot"][p]["brp"]], 19, F_GRASSETTO))
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 6)
		for c in poss:
			var costo := Dati.COSTO_GUERRA_MAGGIORE if m.maggiore(c) else Dati.COSTO_GUERRA_MINORE
			var pp: String = p
			var c2: String = c
			var b := _bottone("%s (%d)" % [Dati.nome(c), costo], func(): _conferma_guerra(pp, c2))
			b.add_theme_font_size_override("font_size", 15)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.add_child(b)
		contenuto.add_child(g)
	if not qualcuna:
		contenuto.add_child(_etichetta("Nessuna dichiarazione possibile.", 17))
	contenuto.add_child(_separatore())
	contenuto.add_child(_bottone("Avanti: scelta delle opzioni", func(): await _decidi({"t": "fine"})))
	_info_selezione()

func _conferma_guerra(p: String, c: String) -> void:
	_apri_popup("Dichiarazione di guerra", "%s dichiara guerra a %s?" % [Dati.nome(p), Dati.nome(c)],
		[["Annulla", _chiudi_popup], ["Dichiara guerra", func(): _chiudi_popup(); await _decidi({"t": "dichiara", "p": p, "c": c})]])

func _pannello_opzioni(r: Dictionary) -> void:
	var p: String = r["p"]
	var pot: Dictionary = m.s["pot"][p]
	contenuto.add_child(_etichetta("%s: BRP %d" % [Dati.nome(p), pot["brp"]], 21, F_GRASSETTO))
	_spiega("Offensiva: si può attaccare e sfondare. Logoramento: tiro sulla tabella con le unità a contatto del nemico. Passo: nessun combattimento.")
	var costo := m.costo_offensiva(p)
	var puo: bool = int(pot["brp"]) >= costo and m.offensiva_permessa(p)
	contenuto.add_child(_bottone("Offensiva (%d BRP)" % costo, func(): await _decidi({"t": "opz", "p": p, "o": "off"}), puo))
	if not m.offensiva_permessa(p):
		_spiega("Nel 1939 la Francia e la Gran Bretagna non possono scegliere l'offensiva.")
	contenuto.add_child(_bottone("Logoramento", func(): await _decidi({"t": "opz", "p": p, "o": "log"})))
	contenuto.add_child(_bottone("Passo", func(): await _decidi({"t": "opz", "p": p, "o": "pas"})))

func _pannello_movimento(sfr: bool) -> void:
	if sfr:
		_spiega("I corazzati entrati nello sfondamento possono muovere ancora e attaccare di nuovo, insieme alle unità che non hanno ancora attaccato. Clic su un esagono nemico adiacente per attaccare.")
	else:
		_spiega("Clic su una tua unità e poi su un esagono verde. Le unità in un porto con flotte sufficienti possono sbarcare via mare.")
	if sel_esagono != "" and m.unita_in(sel_esagono).size() > 0:
		contenuto.add_child(_etichetta("Unità in %s:" % m.nome_esagono(sel_esagono), 18, F_GRASSETTO))
		for uid in m.unita_in(sel_esagono):
			var mobile := m.puo_muovere(uid, sfr) and m.raggiungibili(uid, sfr).size() > 0
			var testo := m.descrizione_unita(uid)
			if uid == sel_unita:
				testo = "> " + testo
			var u2: String = uid
			var b := _bottone(testo, func(): sel_unita = u2; _aggiorna(), mobile)
			b.add_theme_font_size_override("font_size", 15)
			contenuto.add_child(b)
	if not attacco.is_empty() and sfr:
		_pannello_attacco()
	contenuto.add_child(_separatore())
	contenuto.add_child(_bottone("Fine dello sfruttamento" if sfr else "Fine del movimento", func(): sel_unita = ""; attacco = {}; await _decidi({"t": "fine"})))
	_info_selezione()

func _pannello_combattimento() -> void:
	_spiega("Clic su un esagono nemico in rosso per preparare l'attacco. L'aviazione entro 4 esagoni può appoggiarlo.")
	if not attacco.is_empty():
		_pannello_attacco()
	contenuto.add_child(_separatore())
	contenuto.add_child(_bottone("Fine dei combattimenti", func(): attacco = {}; await _decidi({"t": "fine"})))
	_info_selezione()

func _pannello_attacco() -> void:
	var h: String = attacco["h"]
	var sfr: bool = attacco.get("sf", false)
	contenuto.add_child(_etichetta("Attacco su %s" % m.nome_esagono(h), 20, F_GRASSETTO))
	var dif := []
	for uid in m.terrestri_in(h):
		dif.append(m.descrizione_unita(uid))
	contenuto.add_child(_etichetta("Difensori: " + ", ".join(dif), 15))
	contenuto.add_child(_etichetta("Attaccanti:", 16, F_GRASSETTO))
	for uid in m.attaccanti_possibili(h, sfr):
		var cb := CheckBox.new()
		cb.text = "%s (%s)" % [m.descrizione_unita(uid), m.s["u"][uid]["h"]]
		cb.button_pressed = attacco["u"].has(uid)
		cb.add_theme_font_size_override("font_size", 15)
		var u2: String = uid
		cb.toggled.connect(func(on): _scegli_attaccante(u2, on))
		contenuto.add_child(cb)
	var aerei := m.aerei_possibili(h, m.s["lato"])
	if aerei.size() > 0:
		contenuto.add_child(_etichetta("Appoggio aereo:", 16, F_GRASSETTO))
		for uid in aerei:
			var cb := CheckBox.new()
			cb.text = "%s (%s)" % [m.descrizione_unita(uid), m.s["u"][uid]["h"]]
			cb.button_pressed = attacco["av"].has(uid)
			cb.add_theme_font_size_override("font_size", 15)
			var u2: String = uid
			cb.toggled.connect(func(on): _scegli_aereo(u2, on))
			contenuto.add_child(cb)
	if attacco["u"].size() > 0:
		var v := m.valuta_attacco(h, attacco["u"], attacco["av"])
		var col := int(v["col"])
		var testo := "Attacco %d contro difesa %d" % [v["att"], v["dif"]]
		if v["motivo"] != "":
			testo += " (difesa raddoppiata: %s)" % v["motivo"]
		if v["aerei_dif"].size() > 0:
			testo += ", con appoggio aereo nemico"
		if int(v["spost"]) != 0:
			testo += ", inverno russo"
		contenuto.add_child(_etichetta(testo, 16))
		if col < 0:
			contenuto.add_child(_etichetta("Rapporto inferiore a 1 contro 4: attacco impossibile.", 16, F_GRASSETTO, C_ROSSO))
		else:
			contenuto.add_child(_etichetta("Colonna %s: %s" % [Dati.COLONNE[col], _riga_crt(col)], 17, F_GRASSETTO, C_ROSSO))
		var ok: bool = col >= 0 and m.cooperazione_ok(attacco["u"])
		if not m.cooperazione_ok(attacco["u"]):
			contenuto.add_child(_etichetta("Fino al 1941 britannici e francesi non possono attaccare insieme.", 15, F_CORSIVO, C_ROSSO))
		contenuto.add_child(_bottone("Attacca!", _esegui_attacco, ok))
	contenuto.add_child(_bottone("Annulla", func(): attacco = {}; _aggiorna()))

func _riga_crt(col: int) -> String:
	var parti := []
	for i in 6:
		parti.append("%d:%s" % [i + 1, Dati.CRT[i][col]])
	return " ".join(parti)

func _scegli_attaccante(uid: String, on: bool) -> void:
	if on and not attacco["u"].has(uid):
		attacco["u"].append(uid)
	elif not on:
		attacco["u"].erase(uid)
	_aggiorna()

func _scegli_aereo(uid: String, on: bool) -> void:
	if on and not attacco["av"].has(uid):
		attacco["av"].append(uid)
	elif not on:
		attacco["av"].erase(uid)
	_aggiorna()

func _esegui_attacco() -> void:
	var d := {"t": "attacca", "h": attacco["h"], "u": attacco["u"].duplicate(), "av": attacco["av"].duplicate()}
	attacco = {}
	var res = await _decidi(d)
	if res is Dictionary and res.get("ok", false) and res.has("risultato"):
		var r: Dictionary = res["risultato"]
		var testo: String = "[b]%s[/b]" % r["testo"]
		if r["perdite_att"].size() > 0:
			testo += "\n\nPerdite dell'attaccante: " + ", ".join(r["perdite_att"])
		if r["perdite_dif"].size() > 0:
			testo += "\n\nPerdite del difensore: " + ", ".join(r["perdite_dif"])
		_apri_popup("Esito del combattimento", testo, [["Continua", _chiudi_popup]])

func _pannello_avanzata(r: Dictionary) -> void:
	var h: String = r["h"]
	_spiega("L'esagono %s è libero: puoi avanzare con al massimo 2 unità che hanno attaccato. I corazzati che avanzano dopo uno sfondamento possono sfruttarlo." % m.nome_esagono(h))
	var scelte: Dictionary = _avanza_scelte
	for uid in r["u"]:
		if not scelte.has(uid):
			scelte[uid] = scelte.size() < 2
		var cb := CheckBox.new()
		cb.text = m.descrizione_unita(uid)
		cb.button_pressed = scelte[uid]
		var u2: String = uid
		cb.toggled.connect(func(on): scelte[u2] = on)
		contenuto.add_child(cb)
	contenuto.add_child(_bottone("Avanza", func():
		var lista := []
		for uid in scelte:
			if scelte[uid]:
				lista.append(uid)
		_avanza_scelte = {}
		await _decidi({"t": "avanza", "u": lista.slice(0, 2)})))
	contenuto.add_child(_bottone("Resta sul posto", func(): _avanza_scelte = {}; await _decidi({"t": "fine"})))

func _pannello_costruzione() -> void:
	_spiega("Scegli un'unità dalla riserva e poi una città della tua patria rifornita (evidenziata). Le unità americane nascono negli Stati Uniti.")
	for p in m.costruttori():
		var pot: Dictionary = m.s["pot"][p]
		contenuto.add_child(_etichetta("%s: BRP %d" % [Dati.nome(p), pot["brp"]], 19, F_GRASSETTO))
		var gruppi := {}
		for e in m.s["pool"][p]:
			var k := "%s|%d|%d" % [e[0], e[1], e[2]]
			gruppi[k] = int(gruppi.get(k, 0)) + 1
		var chiavi := gruppi.keys()
		chiavi.sort()
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", 6)
		g.add_theme_constant_override("v_separation", 6)
		for k in chiavi:
			var parti: PackedStringArray = k.split("|")
			var e := [parti[0], int(parti[1]), int(parti[2])]
			var costo := m.costo_unita(e)
			var nome := _nome_breve(e)
			var testo := "%s x%d (%d)" % [nome, gruppi[k], costo]
			var pp: String = p
			var sel: bool = not costr.is_empty() and costr["p"] == p and str(costr["e"][0]) == str(e[0]) and int(costr["e"][1]) == int(e[1]) and int(costr["e"][2]) == int(e[2])
			var b := _bottone(("> " if sel else "") + testo, func(): _scegli_costruzione(pp, e), int(pot["brp"]) >= costo and m.luoghi_costruzione(p, e[0]).size() > 0)
			b.add_theme_font_size_override("font_size", 14)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g.add_child(b)
		contenuto.add_child(g)
	if not costr.is_empty() and costr["p"] == "USA":
		contenuto.add_child(_bottone("Costruisci negli Stati Uniti", func():
			var i := _indice_pool("USA", costr["e"])
			costr = {}
			if i >= 0:
				await _decidi({"t": "costruisci", "p": "USA", "i": i, "h": "USA"})))
	contenuto.add_child(_separatore())
	contenuto.add_child(_bottone("Fine della costruzione", func(): costr = {}; await _decidi({"t": "fine"})))
	_info_selezione()

func _nome_breve(e: Array) -> String:
	match str(e[0]):
		"fan": return "Fanteria %d-%d" % [e[1], e[2]]
		"cor": return "Corazzati %d-%d" % [e[1], e[2]]
		"par": return "Aviotrasp. %d-%d" % [e[1], e[2]]
		"rim": return "Rimpiazzi 1-3"
		"avi": return "Aviazione %d" % e[1]
		"flo": return "Flotta %d" % e[1]
	return str(e[0])

func _scegli_costruzione(p: String, e: Array) -> void:
	costr = {"p": p, "e": e, "t": e[0]}
	_aggiorna()

func _pannello_sr() -> void:
	_spiega("Ridispiegamento strategico: sposta unità lontane dal nemico lungo territorio amico o via mare fra porti amici.")
	for p in m.potenze_del_lato(m.s["lato"]):
		contenuto.add_child(_etichetta("%s: %d ridispiegamenti rimasti" % [Dati.nome(p), max(0, m.sr_rimasti(p))], 16))
	if sel_esagono != "" and m.unita_in(sel_esagono).size() > 0:
		contenuto.add_child(_etichetta("Unità in %s:" % m.nome_esagono(sel_esagono), 18, F_GRASSETTO))
		for uid in m.unita_in(sel_esagono):
			var ok := m.destinazioni_sr(uid).size() > 0
			var testo := m.descrizione_unita(uid)
			if uid == sel_unita:
				testo = "> " + testo
			var u2: String = uid
			var b := _bottone(testo, func(): sel_unita = u2; _aggiorna(), ok)
			b.add_theme_font_size_override("font_size", 15)
			contenuto.add_child(b)
	contenuto.add_child(_separatore())
	contenuto.add_child(_bottone("Fine del turno", func(): sel_unita = ""; await _decidi({"t": "fine"})))
	_info_selezione()

func _aggiorna_evidenze(r: Dictionary) -> void:
	var ragg := []
	var bers := []
	var selez := []
	if sel_esagono != "" and sel_esagono != "USA":
		selez.append(sel_esagono)
	if _mio_turno():
		match r["k"]:
			"movimento", "sfruttamento":
				var sfr: bool = r["k"] == "sfruttamento"
				if sel_unita != "" and m.s["u"].has(sel_unita):
					ragg = m.raggiungibili(sel_unita, sfr).keys()
				if sfr:
					bers = _bersagli(true)
				if not attacco.is_empty():
					selez = [attacco["h"]]
			"combattimento":
				bers = _bersagli(false)
				if not attacco.is_empty():
					selez = [attacco["h"]]
					for uid in attacco["u"]:
						ragg.append(m.s["u"][uid]["h"])
			"costruzione":
				if not costr.is_empty():
					ragg = m.luoghi_costruzione(costr["p"], costr["t"])
			"ridispiegamento":
				if sel_unita != "":
					ragg = m.destinazioni_sr(sel_unita)
			"avanzata":
				selez = [r["h"]]
	ragg.erase("USA")
	vista.evidenzia("raggiungibili", ragg)
	vista.evidenzia("bersagli", bers)
	vista.evidenzia("selezione", selez)

func _bersagli(sfr: bool) -> Array:
	var vicini := {}
	for uid in m.s["u"]:
		var u: Dictionary = m.s["u"][uid]
		if m.lato(u["n"]) != m.s["lato"] or not Motore._terrestre(u["t"]) or u["h"] == "USA":
			continue
		if sfr and not m.s["sfrutt"].has(uid):
			continue
		for v in D.esagoni[u["h"]]["vicini"]:
			vicini[v] = true
	var out := []
	for v in vicini:
		if m.attaccanti_possibili(v, sfr).size() > 0:
			out.append(v)
	return out

# =====================================================================================
# Gioco online
# =====================================================================================

func _menu_online() -> void:
	var v := VBoxContainer.new()
	for c in popup.get_children():
		c.queue_free()
	popup.visible = true
	var f := ColorRect.new()
	f.color = Color(0, 0, 0, 0.45)
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(f)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(cc)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(640, 0)
	cc.add_child(p)
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(titolo("GIOCO ONLINE", 26))
	v.add_child(_etichetta("Due giocatori: chi crea la stanza sceglie lo schieramento, l'altro entra con il codice di 4 lettere.", 17, F_CORSIVO))
	var nome := LineEdit.new()
	nome.placeholder_text = "Il tuo nome"
	nome.text = str(rete.load_session().get("nome", ""))
	v.add_child(nome)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	h.add_child(_bottone("Crea: gioco l'Asse", func(): _crea_stanza(nome.text, "asse")))
	h.add_child(_bottone("Crea: gioco gli Alleati", func(): _crea_stanza(nome.text, "alleati")))
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 10)
	v.add_child(h2)
	var cod := LineEdit.new()
	cod.placeholder_text = "Codice"
	cod.custom_minimum_size = Vector2(160, 0)
	h2.add_child(cod)
	h2.add_child(_bottone("Entra nella stanza", func(): _entra_stanza(nome.text, cod.text.strip_edges().to_upper())))
	var sess := rete.load_session()
	if str(sess.get("room", "")) != "":
		v.add_child(_bottone("Rientra nella stanza %s" % sess["room"], func(): _entra_stanza(nome.text if nome.text != "" else "Giocatore", str(sess["room"]))))
	v.add_child(_bottone("Chiudi", _chiudi_popup))

func _crea_stanza(nome: String, lato: String) -> void:
	if nome.strip_edges() == "":
		nome = "Giocatore"
	rete._save({"nome": nome})
	_messaggio("Creo la stanza...")
	var seme := int(Time.get_unix_time_from_system()) % 1000000 + randi() % 1000
	var c := await rete.create_room(nome, {"modo": modo, "lato_host": lato, "seme": seme})
	if c == "":
		_apri_popup("Errore", "Impossibile creare la stanza: %s" % rete.last_error, [["Chiudi", _chiudi_popup]])
		return
	codice = c
	posto = 0
	rete.remember_room(codice, 0)
	_attendi_ospite(lato, seme)

func _attendi_ospite(lato: String, seme: int) -> void:
	_apri_popup("Stanza %s" % codice, "Comunica il codice [b]%s[/b] all'avversario. La partita comincia quando entra." % codice, [["Annulla", func(): rete.close_room(codice); _chiudi_popup()]])
	while popup.visible:
		await get_tree().create_timer(2.0).timeout
		var st := await rete.room(codice)
		var seats: Dictionary = Rete._as_dict(st.get("seats", {}))
		if seats.has("1"):
			await rete.start_room(codice, {"modo": modo, "seme": seme, "host": lato})
			_chiudi_popup()
			_avvia_online(lato, {"modo": modo, "seme": seme})
			return

func _entra_stanza(nome: String, c: String) -> void:
	if c.length() != 4:
		_mostra_toast("Il codice ha 4 lettere.")
		return
	if nome.strip_edges() == "":
		nome = "Giocatore"
	rete._save({"nome": nome})
	_messaggio("Entro nella stanza %s..." % c)
	var p := await rete.join_room(c, nome, 2)
	if p < 0:
		_apri_popup("Errore", "Stanza non trovata o già piena. %s" % rete.last_error, [["Chiudi", _chiudi_popup]])
		return
	codice = c
	posto = p
	rete.remember_room(codice, posto)
	# aspetta l'avvio della partita
	_apri_popup("Stanza %s" % c, "Sei nella stanza. Attendi che l'altro giocatore avvii la partita.", [])
	for i in 300:
		var st := await rete.room(codice)
		if st.get("status", "") == "playing" and st.has("game"):
			var g = JSON.parse_string(str(st["game"]))
			_chiudi_popup()
			var host: String = g["host"]
			var mio := host if posto == 0 else ("alleati" if host == "asse" else "asse")
			_avvia_online(mio, g)
			return
		await get_tree().create_timer(2.0).timeout
	_chiudi_popup()

func _avvia_online(lato: String, g: Dictionary) -> void:
	online = true
	mio_lato = lato
	m = Motore.new(D)
	m.nuova(str(g["modo"]), int(g["seme"]))
	umani = {"asse": true, "alleati": true}
	n_applicate = 0
	_avvia()
	_mostra_toast("Partita online: giochi %s." % ("l'Asse" if lato == "asse" else "gli Alleati"))

func _decidi_online(d: Dictionary) -> Dictionary:
	# prova sul motore locale una copia: se non è valida non la invia
	var prova := Motore.new(D)
	prova.importa(m.esporta())
	var r := prova.applica(d)
	if not r["ok"]:
		_mostra_toast(r.get("msg", "non valido"), 2.5)
		return r
	_invio_in_corso = true
	var ok := await rete.post_decision(codice, n_applicate, d)
	_invio_in_corso = false
	if not ok:
		_mostra_toast("Invio non riuscito, riprova. %s" % rete.last_error, 3.0)
		return {"ok": false}
	var prima := _prima_di_applicare(d)
	var res := m.applica(d)
	n_applicate += 1
	_dopo_decisione(d, res, prima)
	return res

func _ciclo_online(delta: float) -> void:
	_attesa_rete -= delta
	if _attesa_rete > 0 or _invio_in_corso:
		return
	_attesa_rete = 1.5
	_sincronizza()

var _sincro_in_corso := false

func _sincronizza() -> void:
	if _sincro_in_corso:
		return
	_sincro_in_corso = true
	var nuove := await rete.get_decisions(codice, n_applicate)
	var chiavi := nuove.keys()
	chiavi.sort()
	for k in chiavi:
		if int(k) != n_applicate:
			break
		var d: Dictionary = nuove[k]
		var prima := _prima_di_applicare(d)
		var res := m.applica(d)
		n_applicate += 1
		_dopo_decisione(d, res, prima)
	_sincro_in_corso = false
