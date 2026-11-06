# frozen_string_literal: true

module Catanat
  # Synthèse de l'indemnisation par item du barème (annexe 2/4 CATANAT) : pour
  # chaque item, le total des montants (bio et non bio) des lignes du bloc
  # d'indemnisation qui portent cet item est écrit dans l'annotation
  # « Montant estimé – <item> (F) ». Le plafond, le « Montant plafonné »
  # (MIN des deux) et le montant de l'indemnisation globale sont des formules
  # de la démarche : les formules ne savent pas sommer les lignes d'un bloc
  # selon une colonne (pas de SOMME.SI).
  #
  #   sources:
  #     - bloc: "Plafond par famille"            # bloc d'annotations lu
  #       cle: "Famille (récapitulatif)"         # colonne portant l'item
  #       montant: "Montant théorique total (F)" # colonne additionnée
  #       items: ["Vanille", ...]                # items du barème
  #   champ_montant: "Montant estimé – {item} (F)" (défaut)
  #
  # Une section masquée par sa condition n'existe pas pour l'API : un bloc ou
  # une annotation absents sont ignorés.
  class SyntheseIndemnisation < FieldChecker
    include EcritureBloc

    CHAMP_MONTANT = 'Montant estimé – {item} (F)'

    def version
      super + 1
    end

    def required_fields
      super + %i[sources]
    end

    def authorized_fields
      super + %i[champ_montant]
    end

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      changed = Array(@params[:sources]).map { |source| synthese(source.stringify_keys) }.any?
      dossier_updated(@dossier) if changed
    end

    private

    # Retourne un booléen de statut (comme save/update), pas un prédicat
    # rubocop:disable Naming/PredicateMethod
    def synthese(source)
      bloc = SetAnnotationValue.get_annotation(@dossier, source['bloc'])
      return false unless bloc

      items = Array(source['items'])
      totaux = items.index_with { 0 }
      Array(bloc.rows).each do |row|
        cle = valeur(row, source['cle'])
        next if cle.blank?

        item = option_equivalente(cle, items)
        if totaux.key?(item)
          totaux[item] += valeur(row, source['montant']).to_f.round
        else
          Rails.logger.warn("Dossier #{@dossier.number} : '#{cle}' du bloc '#{source['bloc']}' n'est pas un item du barème")
        end
      end
      totaux.map { |item, total| ecrit_montant(item, total) }.any?
    end
    # rubocop:enable Naming/PredicateMethod

    def ecrit_montant(item, total)
      label = (@params[:champ_montant] || CHAMP_MONTANT).gsub('{item}', item)
      return false unless SetAnnotationValue.get_annotation(@dossier, label)

      SetAnnotationValue.set_value(@dossier, @demarche.instructeur, label, total)
    end
  end
end
