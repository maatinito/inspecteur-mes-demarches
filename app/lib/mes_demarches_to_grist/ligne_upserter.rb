# frozen_string_literal: true

require_relative 'grist_ref'

module MesDemarchesToGrist
  # Upsert des lignes d'une table Grist liée au dossier, clé (Dossier, Ligne).
  #
  # L'index de ligne comme clé rend tout dédoublonnage inutile : deux lignes
  # source identiques restent deux lignes distinctes, et un nouveau passage
  # réécrit les mêmes clés au lieu de créer des doublons.
  #
  # La clé Dossier passe par GristRef : si la colonne est une référence, la
  # valeur métier doit être encodée en recherche, sinon Grist n'écrit rien.
  class LigneUpserter
    def initialize(table, dossier_col_id: 'Dossier', ligne_col_id: 'Ligne', field_metadata: {})
      @table = table
      @dossier_col_id = dossier_col_id
      @ligne_col_id = ligne_col_id
      @field_metadata = field_metadata
    end

    def upsert_lignes(cle_dossier, lignes)
      return 0 if lignes.empty?

      records = lignes.each_with_index.map do |ligne, index|
        cle = { @dossier_col_id => cle_encodee(cle_dossier), @ligne_col_id => index + 1 }
        { require: cle, fields: ligne.merge(cle) }
      end

      @table.upsert_records(records)
      records.size
    end

    # Supprime les lignes dont l'index dépasse le nombre de lignes du fichier.
    # Sans cela, un fichier corrigé à la baisse laisserait des lignes fantômes.
    def supprimer_orphelins(cle_dossier, nb_lignes)
      existantes = @table.find_by(@dossier_col_id, cle_encodee(cle_dossier))
      orphelins = existantes.select { |r| r.dig('fields', @ligne_col_id).to_i > nb_lignes }.map { |r| r['id'] }
      return 0 if orphelins.empty?

      @table.delete_records(orphelins)
      Rails.logger.info "ExcelVersGrist: #{orphelins.size} ligne(s) orpheline(s) supprimée(s)"
      orphelins.size
    end

    private

    def cle_encodee(valeur)
      GristRef.encode_key(valeur, @field_metadata.dig(@dossier_col_id, :type))
    end
  end
end
