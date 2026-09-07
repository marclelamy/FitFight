import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Politique de confidentialité | FitFight",
  description:
    "Comment FitFight collecte, utilise, partage et supprime les données de compte, de défis et de pas de Santé d’Apple.",
  robots: { index: true, follow: true },
};

export default function PrivacyPage() {
  return (
    <main className="legal-page" lang="fr">
      <header className="legal-header">
        <Link className="brand" href="/" aria-label="Accueil FitFight">
          <span className="brand-mark">FF</span>
          <span>FitFight</span>
        </Link>
        <nav className="legal-nav" aria-label="Confidentialité et assistance">
          <Link href="/fr/privacy" aria-current="page">Confidentialité</Link>
          <Link href="/fr/support">Assistance</Link>
        </nav>
      </header>

      <article className="legal-content">
        <p className="eyebrow">VOS DONNÉES, EN TOUTE CLARTÉ</p>
        <h1>Politique de confidentialité</h1>
        <p className="legal-updated">En vigueur le 5 septembre 2026</p>
        <p className="legal-intro">
          FitFight permet à des participants identifiés de comparer le nombre de pas
          enregistrés pendant un défi privé. Cette politique décrit les données utilisées
          par l’app FitFight pour iPhone et son site d’assistance.
        </p>

        <section>
          <h2>Données collectées</h2>
          <ul>
            <li>
              <strong>Données du compte :</strong> votre identifiant Connexion avec Apple,
              votre adresse e-mail, qui peut être une adresse relais privée Apple, votre nom
              lorsqu’Apple le fournit, le nom d’utilisateur FitFight que vous choisissez et
              un identifiant Apple chiffré, réservé au serveur, permettant de déconnecter
              Connexion avec Apple lorsque vous supprimez votre compte.
            </li>
            <li>
              <strong>Données des défis :</strong> les noms d’utilisateur invités, le gage,
              la durée, l’état de participation, les scores agrégés, le classement et les
              horodatages.
            </li>
            <li>
              <strong>Pas de Santé d’Apple :</strong> avec votre autorisation, FitFight lit
              le nombre de pas et envoie le total fusionné pour la période exacte de chaque
              défi, ainsi que les totaux quotidiens nécessaires aux graphiques.
            </li>
            <li>
              <strong>Bugs et demandes :</strong> le titre, le détail, les votes et les
              commentaires que vous publiez sur le tableau dans l’app, visibles des autres
              utilisateurs FitFight connectés avec votre nom d’utilisateur.
            </li>
            <li>
              <strong>Assistance et fonctionnement :</strong> les messages envoyés à
              l’assistance et des journaux serveur limités, comme l’heure de la requête,
              l’adresse IP, les informations sur l’appareil ou le navigateur et les détails
              d’erreur nécessaires à la sécurité et au fonctionnement du service.
              Des diagnostics privés enregistrent aussi la durée des lectures de Santé
              et des requêtes réseau, leur réussite ou leur échec, la version de l’app
              et la taille des requêtes. Ces mesures ne contiennent ni nombre de pas
              ni échantillons Santé bruts et ne sont pas partagées avec les participants.
            </li>
          </ul>
        </section>

        <section>
          <h2>Santé d’Apple</h2>
          <p>
            L’accès à Santé d’Apple est en lecture seule et limité au nombre de pas. FitFight
            n’écrit aucune donnée dans Santé d’Apple. L’app actuelle n’envoie pas aux serveurs
            FitFight les échantillons Santé bruts, entraînements, itinéraires, fréquences
            cardiaques ni métadonnées d’appareil ou de source.
          </p>
          <p>
            Les participants d’un même défi privé peuvent voir les noms d’utilisateur, le
            total agrégé de pas du défi, les totaux quotidiens affichés dans le graphique,
            le classement, le gage et la durée. Ils ne reçoivent jamais les échantillons
            Santé bruts ni l’historique Santé sans rapport avec le défi d’un autre participant.
          </p>
        </section>

        <section>
          <h2>Utilisation des données</h2>
          <p>Nous utilisons ces données pour :</p>
          <ul>
            <li>créer et sécuriser votre compte ;</li>
            <li>créer, gérer, comptabiliser et terminer les défis privés ;</li>
            <li>afficher les classements et l’historique partagé des défis ;</li>
            <li>faire fonctionner le tableau de bugs et de demandes dans l’app ;</li>
            <li>répondre aux demandes d’assistance ;</li>
            <li>détecter les erreurs, abus et problèmes de sécurité.</li>
          </ul>
          <p>
            FitFight ne vend pas de données personnelles, n’affiche pas de publicité et
            n’utilise pas les données du compte ou de Santé pour la publicité, le suivi entre
            apps ou le courtage de données.
          </p>
        </section>

        <section>
          <h2>Prestataires traitant les données</h2>
          <p>
            FitFight utilise Supabase pour l’authentification et la base de données, et Vercel
            pour héberger les API serveur et les traitements planifiés. Ces prestataires
            traitent les données pour FitFight selon leurs conditions de service et de
            sécurité. Nous ne rendons publiques aucune donnée privée de défi ou de Santé.
          </p>
          <p>
            Nous pouvons également communiquer des informations lorsque la loi l’exige,
            pour protéger les utilisateurs ou le service, ou dans le cadre d’un transfert
            d’activité assorti de garanties appropriées.
          </p>
        </section>

        <section>
          <h2>Autorisations, révocation et conservation</h2>
          <p>
            Vous choisissez d’autoriser ou non l’accès à Santé d’Apple. Vous pouvez retirer
            l’accès de FitFight à tout moment dans Santé d’Apple ou les Réglages iOS. La
            révocation interrompt les lectures futures, mais ne modifie pas les données déjà
            utilisées pour comptabiliser un défi.
          </p>
          <p>
            Nous conservons les données du compte, des défis, des bugs et demandes, et des pas
            envoyés tant que
            votre compte existe. Les e-mails d’assistance sont conservés le temps nécessaire
            au traitement de la demande. Les journaux limités de sécurité et de requêtes
            suivent les durées de conservation configurées chez Supabase et Vercel. Des
            données supprimées peuvent rester temporairement dans les sauvegardes ordinaires
            jusqu’à leur expiration, ou plus longtemps lorsque la loi l’exige.
          </p>
          <p>
            Nous conservons au maximum les 100 rapports de durée de synchronisation les
            plus récents de votre compte. Les rapports de plus de sept jours sont supprimés
            lors du prochain envoi de diagnostics par votre app. La suppression du compte
            efface cet historique.
          </p>
        </section>

        <section>
          <h2>Suppression du compte</h2>
          <p>
            Vous pouvez supprimer définitivement votre compte sous <strong>Vous → Réglages
            → Supprimer le compte</strong>, sans contacter l’assistance. La suppression efface
            votre profil et votre nom d’utilisateur, les totaux de pas envoyés, les anciennes
            relations d’amitié, les invitations, participations et scores, les bugs et
            demandes que vous avez publiés, ainsi que tous les
            défis que vous avez créés. Elle vous retire également des défis créés par une
            autre personne.
          </p>
          <p>
            Lorsque FitFight possède un identifiant Connexion avec Apple révocable, l’app
            demande à Apple de le révoquer lors de la suppression du compte FitFight et vous
            déconnecte. Si la révocation automatique est indisponible, l’app explique comment
            déconnecter FitFight dans les réglages Apple. La suppression n’efface aucune donnée
            stockée dans Santé d’Apple et ne supprime pas votre identifiant Apple.
          </p>
        </section>

        <section>
          <h2>Vos choix</h2>
          <p>
            Vous pouvez demander l’accès, la correction ou la suppression des informations
            associées à votre compte. Écrivez à <a href="mailto:marc@marclamy.com">marc@marclamy.com</a>
            depuis l’adresse liée à votre compte afin que nous puissions vérifier la demande.
          </p>
        </section>

        <section>
          <h2>Modifications et contact</h2>
          <p>
            Nous pouvons mettre à jour cette politique lorsque FitFight évolue. La date
            d’entrée en vigueur ci-dessus identifie la version actuelle. Pour toute question
            sur la confidentialité, écrivez à{" "}
            <a href="mailto:marc@marclamy.com?subject=Confidentialit%C3%A9%20FitFight">
              marc@marclamy.com
            </a>.
          </p>
        </section>
      </article>

      <footer className="legal-footer">
        <span>© 2026 FitFight</span>
        <Link href="/fr/support">Assistance</Link>
      </footer>
    </main>
  );
}
