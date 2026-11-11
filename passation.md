# Passation — projet Nox

Document de reprise pour une session Claude Code locale (PC Windows).
Tout ce qui a été décidé jusqu'ici est ici ; le code est sur `main`.

## 1. Préférences de l'utilisateur (à respecter)

- Répondre en français, strictement à ce qui est demandé, sans étapes non
  sollicitées, sans récap final ni disclaimer, réponses courtes.
- Ne pas créer de fichier/document/artifact sans demande explicite.
- **Prévenir avant** toute demande qui dépasserait ~10 % de la session.
- « oui » / « ok » = ne pas développer.

## 2. Vision

Un **assistant de vie** nommé **Nox**, un hibou :

- résumé de la journée, agenda, gestion financière, tâches ;
- intégré à **Home Assistant** (HA), mais **disponible en permanence, même
  hors ligne**, sur **PC Windows** et **téléphone Android** (vraies apps, pas
  de PWA) ;
- finances via **Actual Budget** (+ liaison bancaire à étudier : GoCardless
  fermé aux nouveaux comptes, voir Enable Banking selon version d'Actual,
  sinon import OFX/CSV) ;
- plus tard : **robot physique** (hibou détachable sur une **perche** qui
  héberge le serveur HA et sert de station de recharge), et dans un « avenir
  fou » un **drone** d'intérieur qui le suit.

### Identité

- Nom : **Nox** (veille nocturne, veille techno, « déconnexion du cloud » :
  tout tourne en local). Devise possible : « Nox veille. Tes données dorment
  chez toi. » Mot d'éveil vocal : « Hey Nox ».
- Style retenu : **A — mignon & arrondi** (façon peluche : plumage brun
  `#8B6B4F`, ventre crème, grands yeux ambrés, joues roses, aigrettes
  arrondies). Le design précis sera retravaillé plus tard.
- Espèce de référence : petit-duc / chevêche (compact, léger → drone).
- Plus tard : un **caractère unique qui évolue**.

## 3. Fonctionnalités à garder en tête (liste validée)

★ = prioritaire (MVP assistant)

- **Journée** : ★ brief du matin (agenda, météo, tâches, finances, alertes ;
  rédigé par l'IA de HA, version simple hors ligne) ; ★ vue « Aujourd'hui »
  (timeline, trajets, heure de départ) ; bilan du soir.
- **Agenda & tâches** : ★ agenda unifié via HA, hors ligne ; ★ tâches et
  rappels (récurrence, rappel géolocalisé via zones HA) ; liste de courses
  synchro HA ; saisie rapide en langage naturel.
- **Finances (Actual)** : ★ soldes et « reste à dépenser » par enveloppe ;
  ★ saisie de dépense hors ligne synchronisée ensuite ; ★ alertes (enveloppe
  presque vide, grosse dépense, solde bas) ; échéancier et solde prévisionnel ;
  détection d'abonnements/hausses ; graphiques.
- **Maison (HA)** : état maison dans le brief (alarme, portes, énergie,
  poubelles), raccourcis scènes, coût énergie lié au budget.
- **IA** : chat (« je peux me permettre un resto ? »), voix, suggestions.
- **Transversal** : ★ notifications PC + téléphone ; ★ synchro multi-appareils
  via HA (gestion des conflits) ; verrouillage biométrique + chiffrement
  local ; widgets.

## 4. Plateformes et choix techniques

- **Flutter** (un seul code Windows + Android ; plus tard écran des yeux du
  robot). Animations : dessin en code pour l'instant, **Rive** envisagé.
- **Windows** : compagnon de bureau façon « screenmate » (petit personnage qui
  vit sur le bureau et interagit avec les fenêtres).
- **Android** : bulle flottante au-dessus des apps, widgets, notification
  permanente, synchro en arrière-plan ; distribution par **APK direct** (pas
  de Play Store). Penser à exclure Nox de l'optimisation batterie.
- Données : stockage local d'abord (hors ligne), synchro avec HA quand
  joignable (API HA + jeton longue durée). Accès extérieur à HA : Nabu Casa
  ou VPN (Tailscale) — non encore précisé.
- **Mode sage / espiègle** : simple réglage pour l'instant.

## 5. État actuel du code (étape 1 : compagnon de bureau Windows)

Dépôt : `antoine28boel/nox`, branche `main`. Le build GitHub Actions
(`.github/workflows/build-windows.yml`) passe : analyse, 10 tests, build
Windows, artefact `nox-windows` (zip contenant `nox.exe` + DLL + `data/`).

| Fichier | Rôle |
|---|---|
| `lib/main.dart` | Fenêtre transparente (window_manager 0.5 + flutter_acrylic), icône de notification (tray_manager 0.5), réglages (shared_preferences), lancement au démarrage |
| `lib/nox/brain.dart` | Comportement pur Dart : états `perched/flying/falling/dragged`, perchage, vol en arc, chute, lancer, sommeil, plein écran, modes |
| `lib/nox/desktop.dart` | Interface abstraite du bureau (coordonnées en pixels physiques) |
| `lib/win/win_desktop.dart` | Implémentation Win32 (FFI, package `win32` 5.x) |
| `lib/nox/owl_painter.dart` | Dessin de Nox style A (coordonnées du croquis SVG, pieds en (200,408), échelle 0.4) |
| `lib/nox/pose.dart` | Paramètres de pose par image |
| `lib/nox/nox_view.dart` | Ticker : met à jour le cerveau, déplace la fenêtre, gère le clic-traversant |
| `windows/runner/main.cpp` | Fenêtre « Nox » 200×180, `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE` |
| `test/brain_test.dart` | 10 tests du comportement avec un faux bureau |

Comportements livrés : perchage sur la barre de titre de la fenêtre active
(hors boutons), suivi quand la fenêtre bouge, envol si secouée, chute si
fermée/réduite/agrandie/recouverte, atterrissage sur la barre des tâches,
regard qui suit la souris, clignements, respiration, caresse (yeux ^ ^),
glisser-lancer, sommeil après inactivité (2 min sage / 4 min espiègle),
masqué en plein écran, menu : modes, rappeler, démarrage auto, quitter.

### Jamais testé sur un vrai Windows — à vérifier en premier

1. **Transparence** : pas de rectangle noir/blanc autour de Nox.
2. **Clic-traversant** : `setIgnoreMouseEvents` de window_manager ajoute
   `WS_EX_LAYERED | WS_EX_TRANSPARENT` ; vérifier que Nox **reste visible**
   quand la souris n'est pas sur lui. Sinon : poser `WS_EX_LAYERED` +
   `SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)` une fois au
   démarrage et ne basculer que `WS_EX_TRANSPARENT`.
3. Brève apparition au démarrage (fenêtre montrée avant la config) : si
   gênant, cacher la fenêtre au lancement (`flutter_window.cpp`).
4. Menu de l'icône avec `WS_EX_NOACTIVATE` : vérifier qu'il se ferme bien.
5. Multi-écrans / mise à l'échelle différente par écran.
6. Consommation CPU (ticker 60 fps en continu ; réduire quand il dort).
7. Les « z » du sommeil utilisent une police (OK sous Windows).

## 6. Prochaines étapes prévues

- **Étape 2 — mode espiègle** : chasse au curseur (le hibou fond sur la
  « souris »), plume laissée sur le bureau, picorer une icône, pousser
  légèrement une fenêtre ; tout désactivable.
- Puis : notifications apportées dans le bec, rappels (tape à la vitre, fait
  les cent pas), réaction à la météo/budget, panneau au double-clic (brief,
  agenda, budget, chat).
- Ensuite : app Android (bulle), synchro HA, Actual Budget.

### Infos encore à demander à l'utilisateur (pour la partie HA)

1. Installation HA (HAOS, Docker…) et HACS ?
2. Entités agenda (`calendar.xxx`) et météo.
3. Intégration IA dans HA (Anthropic, OpenAI, Ollama…) ?
4. Service de notification (`notify.mobile_app_xxx`).
5. Version d'Actual Budget et où il tourne.

## 7. Démarrer en local (Windows)

Prérequis : Flutter stable (le CI utilise 3.47.9) et Visual Studio 2022 avec
la charge « Développement Desktop en C++ ».

```bash
git clone https://github.com/antoine28boel/nox.git
cd nox
flutter pub get
flutter test
flutter run -d windows
```

Commits : terminer les messages par les lignes d'attribution habituelles de
Claude Code ; pousser sur `main` (le CI produit l'artefact).
