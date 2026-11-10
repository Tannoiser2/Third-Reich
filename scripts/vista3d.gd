## Tavolo 3D: la mappa originale come tabellone, le pedine originali come segnalini di cartone,
## evidenziazioni degli esagoni e telecamera orbitale.
## Comandi: mouse (sinistro trascina = sposta, destro trascina = ruota/inclina, rotella = zoom),
## trackpad (pizzico = zoom, due dita = sposta), tocco (un dito = sposta, due dita = zoom, rotazione e inclinazione).
class_name Vista3D
extends Node3D

signal esagono_cliccato(id: String)
signal esagono_sopra(id: String)

const LARGHEZZA := 40.0

var D: Dati
var mappa := "advanced"
var altezza := 28.0
var cam: Camera3D
var bersaglio := Vector3.ZERO
var distanza := 34.0
var imbardata := 0.0
var beccheggio := 62.0
var _piano: MeshInstance3D
var _pedine := {}          # uid -> Node3D
var _segnalini := {}       # esagono -> Node3D (controllo)
var _evid := {}            # nome -> MultiMeshInstance3D
var _tex_cache := {}
var _font: Font
var _usa_box: MeshInstance3D
var _tocchi := {}
var _trascina := false
var _premuto := false
var _premuto_pos := Vector2.ZERO
var _ruota := false
var _ultimo_sopra := ""
var tempo_anim := 0.25

func prepara(dati: Dati, quale: String) -> void:
	D = dati
	mappa = quale
	var g: Dictionary = D.griglie[mappa]
	altezza = LARGHEZZA * float(g["img"][1]) / float(g["img"][0])
	_font = load("res://assets/font/Oswald.ttf")
	for c in get_children():
		c.queue_free()
	_pedine.clear()
	_segnalini.clear()
	_evid.clear()
	_frecce = null
	# luce e ambiente
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.08, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.82, 0.76)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.4
	e.ambient_light_energy = 0.42
	env.environment = e
	add_child(env)
	var sole := DirectionalLight3D.new()
	sole.rotation_degrees = Vector3(-58, -32, 0)
	sole.light_energy = 0.62
	sole.shadow_enabled = true
	add_child(sole)
	# tavolo di legno sotto la mappa
	var tavolo := MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(LARGHEZZA * 2.2, altezza * 2.4)
	tavolo.mesh = tm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.22, 0.15, 0.1)
	mt.roughness = 0.9
	tavolo.material_override = mt
	tavolo.position.y = -0.05
	add_child(tavolo)
	# tabellone
	_piano = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(LARGHEZZA, altezza)
	_piano.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/mappa/%s.jpg" % mappa)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.93, 0.93, 0.93)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_piano.material_override = m
	add_child(_piano)
	# bordo del tabellone
	var bordo := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(LARGHEZZA + 0.4, 0.08, altezza + 0.4)
	bordo.mesh = bm
	var mb := StandardMaterial3D.new()
	mb.albedo_color = Color(0.12, 0.11, 0.1)
	bordo.material_override = mb
	bordo.position.y = -0.045
	add_child(bordo)
	# riquadro degli Stati Uniti, a sinistra della mappa
	_usa_box = MeshInstance3D.new()
	var um := BoxMesh.new()
	um.size = Vector3(5.0, 0.06, 7.0)
	_usa_box.mesh = um
	var mu := StandardMaterial3D.new()
	mu.albedo_color = Color(0.35, 0.42, 0.25)
	_usa_box.material_override = mu
	_usa_box.position = Vector3(-LARGHEZZA / 2 - 3.4, 0.0, -altezza / 2 + 4.5)
	add_child(_usa_box)
	var lab := Label3D.new()
	lab.text = "STATI UNITI"
	lab.font = _font
	lab.font_size = 96
	lab.pixel_size = 0.006
	lab.rotation_degrees = Vector3(-90, 0, 0)
	lab.position = _usa_box.position + Vector3(0, 0.05, -3.0)
	lab.modulate = Color(0.95, 0.92, 0.8)
	lab.outline_size = 10
	add_child(lab)
	for nome in ["raggiungibili", "bersagli", "selezione", "ultimo", "sopra"]:
		_evid[nome] = _crea_multimesh(nome)
	cam = Camera3D.new()
	cam.fov = 45
	cam.far = 400
	add_child(cam)
	bersaglio = Vector3(0, 0, -altezza * 0.12)
	_aggiorna_camera()

# -------------------------------------------------------------------------------------
# Frecce: attacchi, appoggio aereo, avanzate, sbarchi
# -------------------------------------------------------------------------------------

var _frecce: Node3D = null

func pulisci_frecce() -> void:
	if _frecce != null:
		for c in _frecce.get_children():
			c.queue_free()

## Disegna una freccia fra due esagoni. arco > 0: traiettoria sollevata (aviazione);
## curva != 0: piega laterale (rotte navali); tratteggio: segmenti alternati.
## rotta navale fra un porto e una costa: esagoni di mare (ricerca in ampiezza); vuota se non trovata
func rotta_mare(da: String, a: String) -> Array:
	if not D.esagoni.has(da) or not D.esagoni.has(a):
		return []
	var arrivo := {}
	for v in D.esagoni[a]["vicini"]:
		if D.esagoni[v]["t"] == 9:
			arrivo[v] = true
	var prec := {}
	var coda := []
	for v in D.esagoni[da]["vicini"]:
		if D.esagoni[v]["t"] == 9:
			prec[v] = ""
			coda.append(v)
	# porti chiusi (la Manica a Portsmouth): si esce anche dai mari dietro la costa vicina
	for v in D.esagoni[da]["vicini"]:
		if D.esagoni[v]["t"] != 9:
			for w in D.esagoni[v]["vicini"]:
				if D.esagoni[w]["t"] == 9 and not prec.has(w):
					prec[w] = ""
					coda.append(w)
	var i := 0
	var trovato := ""
	while i < coda.size() and i < 4000:
		var x: String = coda[i]
		i += 1
		if arrivo.has(x):
			trovato = x
			break
		for w in D.esagoni[x]["vicini"]:
			if D.esagoni[w]["t"] == 9 and not prec.has(w):
				prec[w] = x
				coda.append(w)
	if trovato == "":
		return []
	var out := []
	var c := trovato
	while c != "":
		out.push_front(c)
		c = prec[c]
	return out

## freccia che segue una sequenza di esagoni (rotte navali), smussata
func freccia_percorso(ids: Array, colore: Color, spessore := 1.0, tratteggio := false) -> void:
	if ids.size() < 2:
		return
	if _frecce == null:
		_frecce = Node3D.new()
		add_child(_frecce)
	var r := D.raggio(mappa) * LARGHEZZA
	var pts := []
	for id in ids:
		var q := mondo(id)
		q.y = 0.45
		pts.append(q)
	# accorcia gli estremi verso il centro degli esagoni di partenza e arrivo
	var n0: Vector3 = (pts[1] - pts[0]).normalized()
	pts[0] = pts[0] + n0 * r * 0.3
	var nl: Vector3 = (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	pts[pts.size() - 1] = pts[pts.size() - 1] - nl * r * 0.5
	# smussatura (Chaikin, due passate)
	for k in 2:
		var nuovi := [pts[0]]
		for j in pts.size() - 1:
			var a0: Vector3 = pts[j]
			var a1: Vector3 = pts[j + 1]
			nuovi.append(a0.lerp(a1, 0.25))
			nuovi.append(a0.lerp(a1, 0.75))
		nuovi.append(pts[pts.size() - 1])
		pts = nuovi
	_disegna_punti(pts, colore, r, spessore, tratteggio)

func freccia(da: String, a: String, colore: Color, spessore := 1.0, arco := 0.0, curva := 0.0, tratteggio := false) -> void:
	if da == "" or a == "" or da == a:
		return
	if _frecce == null:
		_frecce = Node3D.new()
		add_child(_frecce)
	var p0 := mondo(da)
	var p2 := mondo(a)
	var r := D.raggio(mappa) * LARGHEZZA
	var dir := (p2 - p0)
	dir.y = 0.0
	var lung := dir.length()
	if lung < 0.01:
		return
	var n := dir / lung
	var lat := Vector3(-n.z, 0, n.x)
	# punto di controllo della curva
	var p1 := (p0 + p2) * 0.5 + lat * curva * lung
	# le frecce partono e arrivano al bordo degli esagoni
	p0 = p0 + n * r * 0.15
	p2 = p2 - n * r * 0.5
	var base_y := 0.45
	var w := r * 0.3 * spessore
	var passi := 24
	var punti := []
	for i in passi + 1:
		var t := float(i) / float(passi)
		var q := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		q.y = base_y + arco * r * 4.0 * t * (1.0 - t)
		punti.append(q)
	_disegna_punti(punti, colore, r, spessore, tratteggio)

func _disegna_punti(punti: Array, colore: Color, r: float, spessore: float, tratteggio: bool) -> void:
	var w := r * 0.3 * spessore
	var lung := 0.0
	for i in punti.size() - 1:
		lung += (punti[i + 1] - punti[i]).length()
	var testa := minf(r * 0.6 * spessore, lung * 0.45)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 120
	mat.albedo_color = colore
	var mb := mat.duplicate() as StandardMaterial3D
	mb.albedo_color = Color(0.05, 0.04, 0.03, colore.a * 0.85)
	mb.render_priority = 119
	# contorno scuro più largo sotto la freccia colorata
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh_freccia(punti, w * (1.7 if k == 0 else 1.0), testa * (1.25 if k == 0 else 1.0), tratteggio, r)
		mi.material_override = mb if k == 0 else mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frecce.add_child(mi)

func _mesh_freccia(punti: Array, w: float, testa: float, tratteggio: bool, r: float) -> ArrayMesh:
	var passi := punti.size() - 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lung_tot := 0.0
	for i in passi:
		lung_tot += (punti[i + 1] - punti[i]).length()
	var percorso := 0.0
	for i in passi:
		var a0: Vector3 = punti[i]
		var a1: Vector3 = punti[i + 1]
		var seg := (a1 - a0).length()
		if percorso + seg > lung_tot - testa * 0.9:
			break
		var acceso := true
		if tratteggio:
			acceso = int(percorso / (r * 0.35)) % 2 == 0
		percorso += seg
		if not acceso:
			continue
		var d2 := a1 - a0
		d2.y = 0
		if d2.length() < 0.0001:
			continue
		d2 = d2.normalized()
		var l2 := Vector3(-d2.z, 0, d2.x) * w * 0.5
		st.add_vertex(a0 - l2)
		st.add_vertex(a0 + l2)
		st.add_vertex(a1 + l2)
		st.add_vertex(a0 - l2)
		st.add_vertex(a1 + l2)
		st.add_vertex(a1 - l2)
	var fine: Vector3 = punti[passi]
	var prima: Vector3 = punti[passi - 2]
	var dt := fine - prima
	dt.y = 0
	dt = dt.normalized()
	var lt := Vector3(-dt.z, 0, dt.x)
	var bp := fine - dt * testa
	bp.y = fine.y
	st.add_vertex(bp - lt * testa * 0.6)
	st.add_vertex(bp + lt * testa * 0.6)
	st.add_vertex(fine + dt * testa * 0.1)
	return st.commit()

## piccolo simbolo di un'ancora (sbarco) o di un aereo sulla mappa: un rombo colorato
func segno(id: String, colore: Color) -> void:
	if _frecce == null:
		_frecce = Node3D.new()
		add_child(_frecce)
	var r := D.raggio(mappa) * LARGHEZZA
	var cyl := CylinderMesh.new()
	cyl.top_radius = r * 0.32
	cyl.bottom_radius = r * 0.32
	cyl.height = 0.01
	cyl.radial_segments = 4
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 121
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = colore
	mi.material_override = mat
	var p := mondo(id)
	mi.position = Vector3(p.x, 0.5, p.z)
	_frecce.add_child(mi)

func _crea_multimesh(nome: String) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cyl := CylinderMesh.new()
	var r := D.raggio(mappa) * LARGHEZZA * 0.97
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 0.02
	cyl.radial_segments = 6
	cyl.rings = 1
	mm.mesh = cyl
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = {"raggiungibili": Color(0.2, 0.85, 0.3, 0.33), "bersagli": Color(0.95, 0.15, 0.1, 0.38),
		"selezione": Color(1.0, 0.85, 0.1, 0.45), "ultimo": Color(0.3, 0.6, 1.0, 0.3), "sopra": Color(1, 1, 1, 0.18)}[nome]
	mat.no_depth_test = false
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi

## posizione nel mondo del centro di un esagono
func mondo(id: String) -> Vector3:
	if id == "USA":
		return _usa_box.position
	var f := D.posizione(id, mappa)
	return Vector3((f.x - 0.5) * LARGHEZZA, 0.0, (f.y - 0.5) * altezza)

func lato_pedina() -> float:
	return D.raggio(mappa) * LARGHEZZA * 1.12

func evidenzia(nome: String, ids: Array) -> void:
	var mmi: MultiMeshInstance3D = _evid[nome]
	var mm := mmi.multimesh
	mm.instance_count = ids.size()
	var y: float = {"raggiungibili": 0.012, "bersagli": 0.016, "selezione": 0.02, "ultimo": 0.008, "sopra": 0.024}[nome]
	for i in ids.size():
		var p := mondo(ids[i])
		var t := Transform3D(Basis().rotated(Vector3.UP, deg_to_rad(30)), Vector3(p.x, y, p.z))
		mm.set_instance_transform(i, t)

# -------------------------------------------------------------------------------------
# Pedine
# -------------------------------------------------------------------------------------

func _texture(nome: String) -> Texture2D:
	if _tex_cache.has(nome):
		return _tex_cache[nome]
	var path := "res://assets/pedine/%s.webp" % nome
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[nome] = t
	return t

static func immagine_unita(u: Dictionary) -> String:
	var n: String = u["n"]
	match u["t"]:
		"flo":
			return "%s_flo" % n
		"rim":
			return "%s_rim" % n
		"avi":
			return "%s_avi_%d4" % [n, int(u["a"])]
	return "%s_%s_%d%d" % [n, u["t"], int(u["a"]), int(u["m"])]

func _crea_pedina(u: Dictionary) -> Node3D:
	var nodo := Node3D.new()
	var lp := lato_pedina()
	var sc := 0.82 if u["t"] in ["avi", "flo"] else 1.0
	var spess := lp * 0.16
	var corpo := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(lp * sc, spess, lp * sc)
	corpo.mesh = bm
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color(0.86, 0.82, 0.7)
	mc.roughness = 0.8
	corpo.material_override = mc
	corpo.position.y = spess / 2
	nodo.add_child(corpo)
	var faccia := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(lp * sc * 0.98, lp * sc * 0.98)
	faccia.mesh = qm
	faccia.rotation_degrees = Vector3(-90, 0, 0)
	faccia.position.y = spess + 0.002
	var mf := StandardMaterial3D.new()
	var tex := _texture(immagine_unita(u))
	if tex == null:
		tex = _texture("%s_fan_23" % u["n"])
	mf.albedo_texture = tex
	# faccia senza luci: i colori restano quelli delle pedine originali
	mf.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mf.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	faccia.material_override = mf
	faccia.name = "Faccia"
	nodo.add_child(faccia)
	if u["t"] == "flo" or u["t"] == "avi":
		var l := Label3D.new()
		l.font = _font
		l.font_size = 64
		l.pixel_size = lp * 0.011
		l.text = str(int(u["a"]))
		l.rotation_degrees = Vector3(-90, 0, 0)
		l.position = Vector3(0, spess + 0.01, lp * 0.22)
		var nero: bool = u["n"] in ["GER"]
		l.modulate = Color(1, 1, 1) if nero else Color(0.05, 0.05, 0.05)
		l.outline_size = 0
		if u["t"] == "avi":
			l.visible = false
		l.name = "Numero"
		nodo.add_child(l)
	nodo.set_meta("spess", spess)
	return nodo

## ridisegna tutte le pedine dallo stato del motore
func aggiorna(st: Dictionary, anima := true, ignora := "") -> void:
	var viste := {}
	var pile := {}
	var ordine: Array = st["u"].keys()
	ordine.sort_custom(func(a, b): return _peso_pila(st["u"][a]) < _peso_pila(st["u"][b]))
	for uid in ordine:
		var u: Dictionary = st["u"][uid]
		var h: String = u["h"]
		if not pile.has(h):
			pile[h] = []
		pile[h].append(uid)
	for h in pile:
		var lista: Array = pile[h]
		var base := mondo(h)
		var lp := lato_pedina()
		for i in lista.size():
			var uid: String = lista[i]
			var u: Dictionary = st["u"][uid]
			viste[uid] = true
			var nodo: Node3D = _pedine.get(uid)
			if nodo == null:
				nodo = _crea_pedina(u)
				add_child(nodo)
				_pedine[uid] = nodo
				nodo.position = base + Vector3(0, 0.6, 0)
			var dest := base
			if h == "USA":
				dest = base + Vector3(-1.6 + (i % 4) * 1.05, 0.03, -1.6 + int(i / 4) * 1.05)
			else:
				var spess: float = nodo.get_meta("spess")
				dest = base + Vector3(i * lp * 0.09, 0.0 + i * (spess + 0.01), i * lp * 0.09)
			var usato: bool = u.get("mv", false) and u.get("at", false)
			_imposta_usata(nodo, u.get("us", false) and u["t"] in ["avi", "flo"])
			# confronto con l'ultima destinazione assegnata, non con la posizione a metà volo:
			# così aggiornamenti ravvicinati (IA contro IA) non fanno rimbalzare le pedine
			var dest_prec: Vector3 = nodo.get_meta("dest", nodo.position)
			var es_prec: String = nodo.get_meta("es", h)
			nodo.set_meta("dest", dest)
			nodo.set_meta("es", h)
			if dest_prec.distance_to(dest) < 0.01:
				continue
			if nodo.has_meta("tw"):
				var tw_prec = nodo.get_meta("tw")
				if tw_prec is Tween and (tw_prec as Tween).is_valid():
					(tw_prec as Tween).kill()
				nodo.remove_meta("tw")
			if anima and uid != ignora:
				var tw := create_tween()
				nodo.set_meta("tw", tw)
				if es_prec != h:
					# cambio di esagono: piccolo salto
					var su := (nodo.position + dest) / 2 + Vector3(0, 0.8, 0)
					tw.tween_property(nodo, "position", su, tempo_anim * 0.5)
					tw.tween_property(nodo, "position", dest, tempo_anim * 0.5)
				else:
					# stesso esagono (pila riordinata): scivola senza saltare
					tw.tween_property(nodo, "position", dest, tempo_anim * 0.4)
			else:
				nodo.position = dest
	for uid in _pedine.keys():
		if not viste.has(uid):
			_pedine[uid].queue_free()
			_pedine.erase(uid)
	_aggiorna_controllo(st)

func _peso_pila(u: Dictionary) -> int:
	match u["t"]:
		"flo": return 0
		"avi": return 1
		"rim": return 2
		"fan": return 3
		"par": return 4
	return 5

func _imposta_usata(nodo: Node3D, usata: bool) -> void:
	var f: MeshInstance3D = nodo.get_node_or_null("Faccia")
	if f == null:
		return
	var m: StandardMaterial3D = f.material_override
	m.albedo_color = Color(0.6, 0.6, 0.6) if usata else Color(0.97, 0.97, 0.97)

## segnalini di controllo sugli esagoni conquistati
func _aggiorna_controllo(st: Dictionary) -> void:
	var visti := {}
	for id in st["ctrl"]:
		var c: String = st["ctrl"][id]
		var orig: String = D.esagoni[id]["n"]
		var atteso: String = Dati.COLONIE.get(orig, orig)
		if c == atteso:
			continue
		visti[id] = true
		var nodo: Node3D = _segnalini.get(id)
		if nodo != null and nodo.get_meta("c") == c:
			continue
		if nodo != null:
			nodo.queue_free()
		nodo = MeshInstance3D.new()
		var qm := QuadMesh.new()
		var lp := lato_pedina() * 0.42
		qm.size = Vector2(lp, lp)
		nodo.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = _texture("ctl_" + c)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		nodo.material_override = m
		nodo.rotation_degrees = Vector3(-90, 0, 0)
		var p := mondo(id)
		nodo.position = p + Vector3(-lp * 0.95, 0.006, -lp * 0.75)
		nodo.set_meta("c", c)
		add_child(nodo)
		_segnalini[id] = nodo
	for id in _segnalini.keys():
		if not visti.has(id):
			_segnalini[id].queue_free()
			_segnalini.erase(id)

func centra_su(id: String) -> void:
	var p := mondo(id)
	var tw := create_tween()
	tw.tween_property(self, "bersaglio", Vector3(p.x, 0, p.z), 0.4)

# -------------------------------------------------------------------------------------
# Telecamera e comandi
# -------------------------------------------------------------------------------------

func _process(_d: float) -> void:
	_aggiorna_camera()

func _aggiorna_camera() -> void:
	if cam == null:
		return
	beccheggio = clampf(beccheggio, 18.0, 89.0)
	distanza = clampf(distanza, 3.0, 60.0)
	bersaglio.x = clampf(bersaglio.x, -LARGHEZZA * 0.62, LARGHEZZA * 0.55)
	bersaglio.z = clampf(bersaglio.z, -altezza * 0.55, altezza * 0.55)
	var b := deg_to_rad(beccheggio)
	var y := deg_to_rad(imbardata)
	var off := Vector3(sin(y) * cos(b), sin(b), cos(y) * cos(b)) * distanza
	cam.position = bersaglio + off
	cam.look_at(bersaglio, Vector3.UP)

func vista_dall_alto() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "beccheggio", 89.0, 0.4)
	tw.tween_property(self, "imbardata", 0.0, 0.4)

func vista_inclinata() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "beccheggio", 55.0, 0.4)

func zoom(f: float) -> void:
	distanza *= f

## punto della mappa sotto lo schermo
func _punto_terra(pos: Vector2) -> Variant:
	var o := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := -o.y / dir.y
	if t < 0:
		return null
	return o + dir * t

func esagono_a(pos: Vector2) -> String:
	var p = _punto_terra(pos)
	if p == null:
		return ""
	var pt: Vector3 = p
	# riquadro USA
	var ub := _usa_box.position
	if absf(pt.x - ub.x) < 2.6 and absf(pt.z - ub.z) < 3.6:
		return "USA"
	var g: Dictionary = D.griglie[mappa]
	var px: float = (pt.x / LARGHEZZA + 0.5) * float(g["img"][0])
	var py: float = (pt.z / altezza + 0.5) * float(g["img"][1])
	var rf: float = (py - float(g["y0"])) / float(g["ry"])
	var cf: float = (px - float(g["x0"]) - float(g["rx"]) * rf) / float(g["cx"])
	# arrotondamento in coordinate cubiche (x = c, z = r)
	var x := cf
	var z := rf
	var yy := -x - z
	var rx := roundf(x)
	var rz := roundf(z)
	var ry := roundf(yy)
	var dx := absf(rx - x)
	var dz := absf(rz - z)
	var dy := absf(ry - yy)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dz > dy:
		rz = -rx - ry
	var k := int(rz) * 1000 + int(rx)
	return D.per_rc.get(k, "")

func _unhandled_input(ev: InputEvent) -> void:
	if cam == null:
		return
	if ev is InputEventScreenTouch:
		var t: InputEventScreenTouch = ev
		if t.pressed:
			_tocchi[t.index] = t.position
			if _tocchi.size() == 1:
				_premuto = true
				_premuto_pos = t.position
				_trascina = false
		else:
			if _tocchi.size() == 1 and _premuto and not _trascina:
				var id := esagono_a(t.position)
				if id != "":
					esagono_cliccato.emit(id)
			_tocchi.erase(t.index)
			if _tocchi.is_empty():
				_premuto = false
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventScreenDrag:
		var d: InputEventScreenDrag = ev
		if not _tocchi.has(d.index):
			_tocchi[d.index] = d.position
		var prima: Vector2 = _tocchi[d.index]
		_tocchi[d.index] = d.position
		if _tocchi.size() == 1:
			if d.position.distance_to(_premuto_pos) > 10:
				_trascina = true
			if _trascina:
				_sposta_schermo(d.position - prima)
		elif _tocchi.size() >= 2:
			_trascina = true
			var keys := _tocchi.keys()
			var altro: int = keys[0] if keys[0] != d.index else keys[1]
			var a: Vector2 = _tocchi[altro]
			var v_prima := prima - a
			var v_dopo := d.position - a
			if v_prima.length() > 4 and v_dopo.length() > 4:
				distanza *= v_prima.length() / v_dopo.length()
				imbardata -= rad_to_deg(v_dopo.angle() - v_prima.angle())
			# trascinamento verticale con due dita: inclinazione
			beccheggio += (d.position.y - prima.y) * 0.08
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMagnifyGesture:
		distanza /= (ev as InputEventMagnifyGesture).factor
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventPanGesture:
		var pg: InputEventPanGesture = ev
		if pg.shift_pressed:
			imbardata += pg.delta.x * 2.0
			beccheggio -= pg.delta.y * 2.0
		else:
			_sposta_schermo(-pg.delta * 12.0)
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distanza *= 0.9
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distanza *= 1.1
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_premuto = true
				_premuto_pos = mb.position
				_trascina = false
			else:
				if _premuto and not _trascina:
					var id := esagono_a(mb.position)
					if id != "":
						esagono_cliccato.emit(id)
				_premuto = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_ruota = mb.pressed
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseMotion:
		var mm: InputEventMouseMotion = ev
		if _premuto and not _tocchi.size() > 0:
			if mm.position.distance_to(_premuto_pos) > 6:
				_trascina = true
			if _trascina:
				_sposta_schermo(mm.relative)
		elif _ruota:
			imbardata -= mm.relative.x * 0.3
			beccheggio += mm.relative.y * 0.25
		else:
			var id := esagono_a(mm.position)
			if id != _ultimo_sopra:
				_ultimo_sopra = id
				evidenzia("sopra", [id] if id != "" and id != "USA" else [])
				esagono_sopra.emit(id)

func _sposta_schermo(delta: Vector2) -> void:
	# sposta il punto inquadrato in modo che la mappa segua il dito
	var vp := get_viewport().get_visible_rect().size
	var scala := distanza * 2.0 * tan(deg_to_rad(cam.fov / 2.0)) / maxf(1.0, vp.y)
	var y := deg_to_rad(imbardata)
	var destra := Vector3(cos(y), 0, -sin(y))
	var avanti := Vector3(-sin(y), 0, -cos(y))
	var corr := 1.0 / maxf(0.35, sin(deg_to_rad(beccheggio)))
	bersaglio -= destra * delta.x * scala
	bersaglio += avanti * delta.y * scala * corr
