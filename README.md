# Nox

Nox est un petit hibou qui vit sur le bureau Windows : il se perche sur les
fenêtres, vole de l'une à l'autre, suit la souris du regard et s'endort quand
tu t'absentes. À terme, il deviendra l'assistant de vie (brief du jour,
agenda, budget Actual) relié à Home Assistant.

## Installer

1. Onglet **Actions** du dépôt → dernier run **Build Windows** réussi.
2. Télécharger l'artefact **nox-windows** et le dézipper.
3. Lancer `nox.exe`.

Nox apparaît en haut de l'écran et va se poser. Son icône est près de
l'horloge (clic gauche ou droit) :

- **Mode sage** / **Mode espiègle**
- **Nichoir (mode travail)** — aussi par **clic droit sur Nox** (et clic
  droit sur l'île pour l'en sortir) : Nox s'installe en haut au centre de
  l'écran, dans une petite île noire où l'on ne voit que ses yeux. Un clic
  sur l'île l'appelle (elle s'agrandit, il écoute) ; un second clic le renvoie.
  L'île se **déplace en la faisant glisser** le long du haut de l'écran ou
  du bas (au-dessus de la barre des tâches) ; Nox retient sa place. Quand la
  souris approche, elle **se rétracte en un fin trait** et laisse passer les
  clics ; survoler le trait une demi-seconde la fait revenir.
- **Rappeler Nox** : le fait revenir près de la souris (quitte le mode travail)
- **Lancer au démarrage de Windows**
- **Quitter**

## Ce qu'il sait faire

- Se percher sur la barre de titre de la fenêtre active (jamais sur les
  boutons réduire / agrandir / fermer).
- Être emporté quand la fenêtre bouge ; s'envoler si on la secoue.
- Tomber puis s'envoler quand sa fenêtre est fermée, réduite, agrandie ou
  recouverte ; se poser sur la barre des tâches.
- Suivre le curseur du regard, cligner des yeux, respirer.
- Se laisser attraper et lancer à la souris.
- Fermer les yeux de plaisir quand on le caresse (curseur sur sa tête).
- S'endormir après 2 min (sage) ou 4 min (espiègle) d'inactivité.
- Disparaître pendant un jeu ou une vidéo en plein écran.
- Ne jamais voler le focus clavier ; les clics passent à travers lui,
  sauf sur son corps.

| | Sage | Espiègle |
|---|---|---|
| Change de place | toutes les 45 s à 2 min | toutes les 8 à 25 s |
| Suit la fenêtre active | non | oui, le plus souvent |

## Développement

```bash
flutter pub get
flutter test          # comportement de Nox (sans Windows)
flutter run -d windows
```

- `lib/nox/brain.dart` : comportement (états, vol, perchage, sommeil).
- `lib/nox/owl_painter.dart` : dessin de Nox (style A).
- `lib/win/win_desktop.dart` : accès aux fenêtres Windows (Win32).
- `lib/main.dart` : fenêtre transparente, icône de notification, réglages.
