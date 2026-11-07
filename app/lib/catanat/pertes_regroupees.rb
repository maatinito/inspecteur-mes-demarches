# frozen_string_literal: true

module Catanat
  # Base des tâches qui regroupent les pertes déclarées dans un bloc du
  # formulaire (cultures, élevages, équipements) et les recopient dans un bloc
  # d'annotations, une ligne par groupe.
  #
  # Une sous-classe définit :
  #   COLONNES : colonnes écrites, dans l'ordre des valeurs de `lignes`
  #   RETENUS : colonnes saisies par l'instructeur, jamais écrites
  #   lignes : les lignes à écrire (une valeur par colonne)
  # Elle peut redéfinir `bloc_destination`, et `ecrit_pertes` pour des
  # écritures complémentaires (en appelant `ecrit_lignes`).
  class PertesRegroupees < FieldChecker
    include EcritureBloc

    def process(demarche, dossier)
      super
      return unless must_check?(dossier)

      dossier_updated(@dossier) if ecrit_pertes
    end

    private

    def bloc_destination = @params[:bloc_destination]

    # Retourne un booléen de statut : vrai si une annotation a changé.
    def ecrit_pertes = ecrit_lignes(lignes)

    def ecrit_lignes(lignes)
      recopie(bloc_destination, lignes, self.class::COLONNES) { |row| avertir_ligne_retiree(row) }
    end

    # Une ligne qui n'a plus de perte déclarée est vidée, sauf les colonnes de
    # l'instructeur : on le signale s'il y avait saisi quelque chose.
    def avertir_ligne_retiree(row)
      saisies = self.class::RETENUS.select { |label| valeur(row, label).to_i.positive? }
      return if saisies.empty?

      Rails.logger.warn("Dossier #{@dossier.number} : une ligne de '#{bloc_destination}' n'a plus de perte déclarée " \
                        "mais garde une saisie de l'instructeur (#{saisies.join(', ')})")
    end
  end
end
