# frozen_string_literal: true

module Excel
  # Descripteur d'une colonne extraite d'une feuille de calcul.
  #
  # `nom` est le nom sanitizé (celui qui sert de clé dans les lignes et de nom
  # de colonne cible) ; `en_tete_brut` conserve l'intitulé d'origine pour les
  # messages d'erreur et le débogage des configurations.
  ColumnDescriptor = Struct.new(:nom, :en_tete_brut, :index, :type_infere)
end
