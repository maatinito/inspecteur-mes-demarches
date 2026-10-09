# frozen_string_literal: true

module Dbs
  # Calculs du carnet de suivi des poussins, sans accès au dossier. `morts` : un élément par jour (index 0 = jour 1),
  # nil pour un jour non saisi (0 est une saisie). Base de l'alerte : l'effectif restant LA VEILLE (spec mère §5).
  module CarnetMortalite
    module_function

    def restant_veille(recu, morts, jour)
      recu - morts.first([jour - 1, 0].max).compact.sum
    end

    def jours_en_alerte(recu, morts, seuil)
      morts.each_with_index.filter_map do |mort, i|
        next if mort.nil?

        base = restant_veille(recu, morts, i + 1)
        i + 1 if base.positive? && mort >= seuil * base
      end
    end

    def dernier_jour_saisi(morts)
      (morts.rindex { |m| !m.nil? } || -1) + 1
    end

    def mortalite_fenetre(recu, morts, fenetre)
      dernier = dernier_jour_saisi(morts)
      return 0.0 if dernier.zero?

      debut = [dernier - fenetre + 1, 1].max
      base = restant_veille(recu, morts, debut)
      return 0.0 unless base.positive?

      (morts[(debut - 1)..(dernier - 1)].compact.sum * 100.0 / base).round(1)
    end
  end
end
