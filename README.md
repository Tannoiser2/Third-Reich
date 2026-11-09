# Third Reich — versione digitale (uso personale)

Il classico Avalon Hill sulla seconda guerra mondiale in Europa, in Godot 4.7, con la scelta fra le due edizioni:

- **Rise and Decline of the Third Reich** (versione base), con la sua mappa originale;
- **Advanced Third Reich**, con la sua mappa e le regole aggiuntive.

Le due versioni condividono la stessa griglia di esagoni (righe A…NN, colonne numerate) e le regole di fondo;
l'Advanced aggiunge diplomazia, inverno russo, petrolio di Ploesti, guerra sottomarina e strategica, aiuti americani all'URSS.

Si gioca nel browser: https://tannoiser2.github.io/Third-Reich/

## Modalità

- **Solitario contro l'IA** con l'Asse o con gli Alleati (livello normale o esperto, che dà all'IA il 20% di BRP in più a inizio anno).
- **Due giocatori sullo stesso schermo** e **IA contro IA** per guardare.
- **Online** in due: chi crea la stanza sceglie lo schieramento, l'altro entra con il codice di 4 lettere.
- **Salvataggio** automatico su Firebase (e sul dispositivo) a ogni cambio di fase; «Continua la partita salvata» riprende.

## Comandi

- Clic su un'unità, poi su un esagono evidenziato in verde. Gli esagoni rossi sono i bersagli d'attacco.
- Mouse: trascina con il tasto sinistro per spostare, tasto destro (o centrale) per ruotare e inclinare, rotella per lo zoom.
- iPad e telefono: un dito sposta la mappa, due dita pizzicano per lo zoom e ruotano; trascinando in verticale con due dita si inclina il tavolo.
- Trackpad del Mac: pizzico per lo zoom, due dita per spostare, Maiusc + due dita per ruotare.
- Pulsanti «Zoom +», «Zoom -», «Dall'alto», «Inclinata».

## Regole implementate (adattamento al computer)

Turni stagionali dall'autunno 1939 all'estate 1945; per ogni schieramento: dichiarazioni di guerra, opzioni
(offensiva 15 BRP, logoramento, passo), movimento con zone di controllo e trasporto via mare, combattimento con la
tabella originale (D, A, Ex, CA/CA1/CA2/CA3 con contrattacco) e appoggio aereo, avanzata e sfruttamento degli
sfondamenti dei corazzati, rifornimenti, costruzione con i BRP, ridispiegamento strategico.

Inoltre: crescita annua dei BRP, conquista dei paesi minori (forze dalla tabella della mappa), patto
tedesco-sovietico alla caduta della Polonia, resa di Francia (con Vichy), Italia, Gran Bretagna, Germania e URSS,
Pearl Harbor nell'inverno 1941, ingresso dell'URSS al più tardi nell'estate 1942, «guerra fasulla» del 1939,
cooperazione anglo-francese e corpo di spedizione britannico limitati fino al 1941, stretti di mare attraversabili
solo dove la mappa ha le frecce rosse. Vittoria a fine guerra secondo gli esagoni obiettivo controllati dall'Asse.

Semplificazioni rispetto al regolamento cartaceo: un'unica opzione per potenza (non per fronte), niente combattimento
navale e aereo separato (le flotte servono per sbarchi e ridispiegamenti, l'aviazione appoggia attacco e difesa),
niente aviotrasporti, partigiani, varianti e scenari 1942/1944. La guerra strategica dell'Advanced è risolta in automatico a inizio anno.

## Struttura

- `scripts/dati.gd` — mappa a esagoni, tabelle, potenze e paesi minori.
- `scripts/motore.gd` — regole e stato della partita (deterministico: online si scambiano solo le decisioni).
- `scripts/ia.gd` — intelligenza artificiale.
- `scripts/vista3d.gd` — tavolo 3D, pedine, telecamera e comandi touch.
- `scripts/main.gd` — interfaccia, menu, salvataggi, gioco online.
- `scripts/rete.gd` — Firebase (Realtime Database REST, accesso anonimo).
- `assets/mappa/` — le due mappe dei moduli di Tabletop Simulator; `assets/pedine/` — le pedine originali.
- `assets/dati/mappa.json` — gli esagoni (terreno, nazione, città, fiumi, stretti) estratti dalla mappa Advanced.

## Firebase

Radice `terzoreich` nel progetto condiviso `flammerouge-f8669`: stanze con registro delle decisioni
(`terzoreich/rooms/<codice>`: `host`, `status`, `cfg`, `game`, `seats`, `members`, `log`) e salvataggi personali
(`terzoreich/salvataggi/<uid>`). Sono strutture già coperte dalla regola comune della ludoteca: non serve una sezione nuova.

## Prove

```
godot --headless --path . -s res://tests/sim.gd -- 7 advanced     # partita completa IA contro IA
tests/sim_breve.sh 3 5 8                                          # più semi, entrambe le versioni
tests/prova_online.sh                                             # finto Firebase + due istanze
godot --headless --path . -s res://tests/ui_umano.gd              # un turno giocato dai pannelli
xvfb-run godot --path . -s res://tests/foto.gd -- attacco         # screenshot in /tmp
python3 tools/controlla_glifi.py                                  # nessun carattere mancante nei font
```

## Pubblicazione

Il workflow `Pubblica` parte a mano (Actions → Pubblica → Run workflow) oppure con un commit che contiene `[pubblica]`
nel messaggio. Pubblica su GitHub Pages e, se ci sono i segreti `CLOUDFLARE_API_TOKEN` e `CLOUDFLARE_ACCOUNT_ID`,
anche sulla ludoteca privata (`thirdreich.ludoteca-digitale.com`).
La cartella `ludoteca/` presenta il gioco nella pagina https://tannoiser2.github.io/.
