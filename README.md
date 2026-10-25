# Notif 🔔

Petite app iPhone (SwiftUI) : tu écris le texte de tes notifications, tu choisis combien tu veux en recevoir et à quel intervalle, tu appuies sur **Lancer**, et ton iPhone les reçoit.

<p align="center"><img src="NotifApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="Icône de l'app"></p>

Sur l'iPhone, l'app s'appelle **Shopify** : c'est le nom affiché sous l'icône et au-dessus des notifications (réglage `INFOPLIST_KEY_CFBundleDisplayName` du projet Xcode).

## Télécharger le .ipa

- **Lien direct (dernière version) :** https://github.com/ramphortpl/testapp/releases/latest/download/NotifApp.ipa
- Ou dans l'onglet **Actions** → dernier run « Build IPA » → artefact **NotifApp-ipa** (un .zip qui contient le .ipa).

Le .ipa est compilé automatiquement sur un Mac de GitHub à chaque push (voir [`.github/workflows/build-ipa.yml`](.github/workflows/build-ipa.yml)).

## Installer l'app sur l'iPhone

> ⚠️ Apple ne permet pas d'installer un .ipa non signé sur un iPhone (sans jailbreak). Il faut le signer avec ton identifiant Apple au moment de l'installation. Un identifiant Apple gratuit suffit.

### Avec Sideloadly (Windows ou Mac) — le plus simple

1. Installe [Sideloadly](https://sideloadly.io) sur ton ordinateur (sur Windows, installe aussi iTunes depuis le site d'Apple si Sideloadly le demande).
2. Branche l'iPhone en USB et accepte « Faire confiance à cet ordinateur ».
3. Glisse `NotifApp.ipa` dans Sideloadly, entre ton identifiant Apple, puis clique sur **Start**.
4. Sur l'iPhone : **Réglages → Confidentialité et sécurité → Mode développeur** → active-le (l'iPhone redémarre).
5. **Réglages → Général → VPN et gestion de l'appareil** → touche ton identifiant Apple → **Faire confiance**.
6. Ouvre l'app **Shopify**, écris ton texte, choisis le nombre et l'intervalle, appuie sur **Lancer** et autorise les notifications 🎉

Avec un identifiant Apple gratuit, l'app expire au bout de **7 jours** : il suffit de la réinstaller avec Sideloadly (tes réglages restent).

### Autres options

- **[AltStore](https://altstore.io)** ou **[SideStore](https://sidestore.io)** : même principe, l'app est signée avec ton identifiant Apple.
- **Tu as un Mac ?** Ouvre `NotifApp.xcodeproj` dans Xcode, choisis ton identifiant Apple dans *Signing & Capabilities → Team*, branche l'iPhone et clique sur ▶︎.
- **Compte Apple Developer payant** : l'app reste valide 1 an au lieu de 7 jours.

## Utilisation

- **Notification** : écris le titre et le message (par défaut « Commande #{n} » et « 50,00 €, 1 article de Boutique en ligne • Tarilo »). `{n}` est remplacé par le numéro de commande. L'aperçu montre le rendu.
- **Numéros de commande** : choisis la tranche (**De** / **À**). Chaque notification reçoit un numéro au hasard dans cette tranche, en ordre croissant comme de vraies commandes (par exemple #1012, #1047, #1083).
- **Son** : chaque notification fait le « cha-ching » complet (1,4 s), joué par iOS comme un son de notification normal (volume de la sonnerie, muet en mode silencieux). Le bouton **Écouter le son** permet de l'entendre.
  - iOS ne joue qu'un son de notification à la fois : si une notification arrive pendant que le son de la précédente joue encore, la nouvelle reste muette. C'est pour ça que l'intervalle minimum est de **2 secondes** en vitesse Normale : chaque son a le temps de finir avant la notification suivante.
- **Nombre de notifications** : tape le nombre ou utilise − / + (jusqu'à 999).
  - iOS ne garde que **64 notifications** programmées d'avance. Au-delà, l'app programme la suite au fur et à mesure : pendant la série, laisse-la en arrière-plan (ne la ferme pas depuis le sélecteur d'apps). L'iPhone peut être verrouillé.
  - Pour rester active en arrière-plan, l'app utilise une piste audio muette, jusqu'à ce que les 64 dernières soient programmées. Elle ne joue aucun son : le « cha-ching » reste celui d'iOS.
- **Vitesse** :
  - **Normale** : intervalle réglable avec − / + et **Secondes / Minutes / Heures** (2 secondes minimum).
  - **Rapide** : une notification par seconde. **Turbo** : deux par seconde. C'est plus rapide que le « cha-ching » (1,4 s), et iOS ne joue qu'un son à la fois.
  - **Un son par notification** (Rapide et Turbo, activé par défaut) : c'est l'app qui joue le « cha-ching » de chaque notification, et les sons se superposent. Ce son suit le volume des médias et sonne même en mode silencieux ; laisse l'app en arrière-plan pendant la série. Si tu la fermes, iOS reprend la main avec son propre son. Désactivé, c'est le son d'iOS, et certaines notifications n'ont pas de son.
- **Lancer** : la première notification arrive après un intervalle, puis une autre à chaque intervalle. Exemple : 3 notifications toutes les 10 secondes arrivent après 10 s, 20 s et 30 s.
- **En cours** : nombre de notifications restantes et compte à rebours avant la prochaine. **Tout arrêter** annule celles qui ne sont pas encore arrivées.
- Jusqu'à 64 notifications, tu peux fermer l'app : elles arrivent quand même. L'app garde tes derniers réglages, et si elle est fermée pendant une longue série, elle reprend la suite à sa réouverture.

### La notification n'apparaît pas ?

- Vérifie **Réglages → Notifications → Shopify** : « Autoriser les notifications » doit être activé.
- Désactive le mode **Concentration / Ne pas déranger**.
- Tu as une **Apple Watch** ? Quand l'iPhone est verrouillé et la montre portée, c'est la montre qui reçoit l'alerte, et l'iPhone ne sonne pas.

## Le code

| Fichier | Rôle |
| --- | --- |
| [`NotifApp/ContentView.swift`](NotifApp/ContentView.swift) | L'écran : texte et aperçu de la notification, nombre, intervalle, boutons Lancer et Tout arrêter |
| [`NotifApp/NotificationScheduler.swift`](NotifApp/NotificationScheduler.swift) | Programme et annule les notifications, tire les numéros de commande et remplace `{n}` |
| [`NotifApp/SeriesRunner.swift`](NotifApp/SeriesRunner.swift) | Fait avancer les séries de plus de 64 notifications, en gardant l'app active en arrière-plan |
| [`NotifApp/IntervalUnit.swift`](NotifApp/IntervalUnit.swift) | Vitesses (Normale, Rapide, Turbo), unités d'intervalle et textes associés |
| `NotifApp/cha_ching.caf` | Son des notifications (1,4 s). Pour en changer, remplace-le par un autre son `.caf` de moins de 30 secondes, avec le même nom (et adapte l'intervalle minimum dans `IntervalUnit.swift` s'il est plus long) |
| `NotifApp/silence.wav` | Piste muette qui garde l'app active en arrière-plan pendant une longue série |
| [`NotifApp/Info.plist`](NotifApp/Info.plist) | Autorise l'audio en arrière-plan (les autres réglages sont générés par Xcode) |
| [`NotifApp/NotifAppApp.swift`](NotifApp/NotifAppApp.swift) | Point d'entrée de l'app ; affiche les notifications même quand l'app est ouverte |

Ce sont des notifications **locales** (`UNUserNotificationCenter`) : pas besoin de serveur ni de certificat push.

## Compiler soi-même (Mac avec Xcode 15 ou plus récent)

```sh
xcodebuild build -project NotifApp.xcodeproj -target NotifApp -configuration Release -sdk iphoneos \
  SYMROOT="$PWD/build" CODE_SIGNING_ALLOWED=NO
mkdir -p Payload && cp -R build/Release-iphoneos/NotifApp.app Payload/
zip -qry NotifApp.ipa Payload
```

---

Développé par PL.
