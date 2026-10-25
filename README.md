# Notif 🔔

Petite app iPhone (SwiftUI) : tu écris le texte de tes notifications, tu choisis combien tu veux en recevoir et à quel intervalle, tu appuies sur **Lancer**, et ton iPhone les reçoit.

<p align="center"><img src="NotifApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="Icône de l'app"></p>

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
6. Ouvre l'app **Notif**, écris ton texte, choisis le nombre et l'intervalle, appuie sur **Lancer** et autorise les notifications 🎉

Avec un identifiant Apple gratuit, l'app expire au bout de **7 jours** : il suffit de la réinstaller avec Sideloadly (tes réglages restent).

### Autres options

- **[AltStore](https://altstore.io)** ou **[SideStore](https://sidestore.io)** : même principe, l'app est signée avec ton identifiant Apple.
- **Tu as un Mac ?** Ouvre `NotifApp.xcodeproj` dans Xcode, choisis ton identifiant Apple dans *Signing & Capabilities → Team*, branche l'iPhone et clique sur ▶︎.
- **Compte Apple Developer payant** : l'app reste valide 1 an au lieu de 7 jours.

## Utilisation

- **Notification** : écris le titre et le message (par défaut « Commande #{n} » et « 50,00 €, 1 article de Boutique en ligne • Tarilo »). `{n}` est remplacé par le numéro de commande. L'aperçu montre le rendu.
- **Numéros de commande** : choisis la tranche (**De** / **À**). Chaque notification reçoit un numéro au hasard dans cette tranche, en ordre croissant comme de vraies commandes (par exemple #1012, #1047, #1083).
- **Son** : chaque notification fait le « cha-ching » complet (1,4 s), joué par iOS comme un son de notification normal (volume de la sonnerie, muet en mode silencieux). Le bouton **Écouter le son** permet de l'entendre.
  - iOS ne joue qu'un son de notification à la fois : si une notification arrive pendant que le son de la précédente joue encore, la nouvelle reste muette. C'est pour ça que l'intervalle minimum est de **2 secondes** : chaque son a le temps de finir avant la notification suivante.
- **Nombre de notifications** : boutons − / + (de 1 à 64, la limite d'iOS).
- **Intervalle** : boutons − / + pour la valeur (2 secondes minimum), et **Secondes / Minutes / Heures** pour l'unité.
- **Lancer** : la première notification arrive après un intervalle, puis une autre à chaque intervalle. Exemple : 3 notifications toutes les 10 secondes arrivent après 10 s, 20 s et 30 s.
- **En cours** : nombre de notifications restantes et compte à rebours avant la prochaine. **Tout arrêter** annule celles qui ne sont pas encore arrivées.
- Tu peux fermer l'app ou verrouiller l'iPhone : les notifications arrivent quand même. L'app garde tes derniers réglages.

### La notification n'apparaît pas ?

- Vérifie **Réglages → Notifications → Notif** : « Autoriser les notifications » doit être activé.
- Désactive le mode **Concentration / Ne pas déranger**.
- Tu as une **Apple Watch** ? Quand l'iPhone est verrouillé et la montre portée, c'est la montre qui reçoit l'alerte, et l'iPhone ne sonne pas.

## Le code

| Fichier | Rôle |
| --- | --- |
| [`NotifApp/ContentView.swift`](NotifApp/ContentView.swift) | L'écran : texte et aperçu de la notification, nombre, intervalle, boutons Lancer et Tout arrêter |
| [`NotifApp/NotificationScheduler.swift`](NotifApp/NotificationScheduler.swift) | Programme et annule les notifications, tire les numéros de commande et remplace `{n}` |
| [`NotifApp/IntervalUnit.swift`](NotifApp/IntervalUnit.swift) | Unités d'intervalle (secondes, minutes, heures) et textes associés |
| `NotifApp/cha_ching.caf` | Son des notifications (1,4 s). Pour en changer, remplace-le par un autre son `.caf` de moins de 30 secondes, avec le même nom (et adapte l'intervalle minimum dans `IntervalUnit.swift` s'il est plus long) |
| [`NotifApp/NotifAppApp.swift`](NotifApp/NotifAppApp.swift) | Point d'entrée de l'app ; affiche les notifications même quand l'app est ouverte |

Ce sont des notifications **locales** (`UNUserNotificationCenter`) : pas besoin de serveur ni de certificat push.

## Compiler soi-même (Mac avec Xcode 15 ou plus récent)

```sh
xcodebuild build -project NotifApp.xcodeproj -target NotifApp -configuration Release -sdk iphoneos \
  SYMROOT="$PWD/build" CODE_SIGNING_ALLOWED=NO
mkdir -p Payload && cp -R build/Release-iphoneos/NotifApp.app Payload/
zip -qry NotifApp.ipa Payload
```
