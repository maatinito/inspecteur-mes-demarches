# frozen_string_literal: true

# Analyse et rédaction du marqueur « mes-demarches: » posé dans la description d'une table
# ou d'une colonne Baserow (contrat référentiel DLNUF §3.2).
#
# Les règles d'analyse (`parse`) sont un portage à l'identique de
# ../mes-demarches/app/lib/referentiel_de_polynesie/marqueur.rb : toute évolution
# des règles se fait dans les deux dépôts.
module Referentiel
  class Marqueur
    CONTRATS_CONNUS = ['1'].freeze
    # Une ligne qui ressemble à un marqueur (même mal écrite) est candidate ; seule la forme
    # exacte « mes-demarches: » est valide. Une faute de frappe doit refuser, pas désactiver.
    CANDIDAT = /\A\s*mes[\s_-]*d[eéÉ]marches?\s*:/i
    PREFIXE = /\A\s*mes-demarches:/i

    LIGNE_REFERENCE_PJ = 'mes-demarches: reference=piece_justificative'
    LIGNE_LISIBLE_DLNUF = 'Référentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.'

    # nil (aucune ligne marqueur), :invalid (marqueur illisible) ou Hash { 'cle' => 'valeur' }
    def self.parse(texte)
      candidates = texte.to_s.each_line.grep(CANDIDAT)
      return nil if candidates.empty?
      return :invalid if candidates.size > 1

      ligne = candidates.first
      return :invalid unless ligne.match?(PREFIXE)

      paires = ligne.sub(PREFIXE, '').split(';').map(&:strip).reject(&:empty?)
      return :invalid if paires.empty?

      resultat = {}
      paires.each do |paire|
        cle, separateur, valeur = paire.partition('=')
        cle = cle.strip.downcase
        return :invalid if separateur.empty? || cle.empty? || resultat.key?(cle) # clé répétée = ambiguë

        resultat[cle] = valeur.strip
      end

      return :invalid if resultat.key?('contrat') && !resultat['contrat'].in?(CONTRATS_CONNUS)

      resultat
    end

    # [:archive, nil] | [:dlnuf, proprietaire] | :invalid
    def self.type_table(texte)
      marqueur = parse(texte)
      return :invalid if marqueur == :invalid
      return [:archive, nil] if marqueur.nil? || !marqueur.key?('referentiel')

      case marqueur['referentiel'].downcase
      when 'archive' then [:archive, nil]
      when 'dlnuf'
        proprietaire = marqueur['proprietaire']
        return :invalid unless proprietaire&.match?(/\A\d+\z/)

        [:dlnuf, proprietaire.to_i]
      else :invalid
      end
    end

    def self.reference_pj?(texte)
      marqueur = parse(texte)
      marqueur.is_a?(Hash) && marqueur['reference']&.downcase == 'piece_justificative'
    end

    # Description d'une table : retire de `existante` toute ligne candidate au marqueur et la ligne
    # lisible du contrat, garde le reste dans l'ordre, puis ajoute les deux lignes en mode :dlnuf.
    def self.description_table(mode:, proprietaire: nil, existante: nil)
      lignes = existante.to_s.each_line.map(&:chomp).reject do |ligne|
        ligne.match?(CANDIDAT) || ligne.strip == LIGNE_LISIBLE_DLNUF
      end
      lignes += [LIGNE_LISIBLE_DLNUF, "mes-demarches: referentiel=DLNUF; proprietaire=#{proprietaire}"] if mode == :dlnuf
      lignes.join("\n")
    end
  end
end
