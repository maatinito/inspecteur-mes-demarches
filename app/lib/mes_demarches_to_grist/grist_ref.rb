# frozen_string_literal: true

module MesDemarchesToGrist
  # Encodage des valeurs destinées à une colonne Grist de type référence.
  #
  # Une colonne `Ref:Table` stocke le *row id* de la ligne visée. Y écrire une
  # valeur métier (le numéro de dossier Mes-Démarches) ne produit rien : Grist
  # n'échoue pas, la cellule reste simplement vide — panne silencieuse constatée
  # en production sur la table Substances du document pesticides, où les valeurs
  # stockées sont de petits entiers (row ids) et non des numéros de dossier.
  #
  # L'encodage ["l", valeur] demande à Grist de *rechercher* la ligne dont la
  # colonne visible vaut `valeur`, et d'en stocker le row id. C'est la seule
  # forme robuste quand on ne connaît que la clé métier.
  #
  # Vaut pour l'écriture comme pour le filtrage : chercher une ligne en filtrant
  # une colonne Ref sur la clé métier ne matche jamais non plus.
  module GristRef
    LOOKUP_MARKER = 'l'
    REF_PREFIX = 'Ref:'

    module_function

    # RefList est volontairement exclu : il attend une liste de row ids
    # (["L", id, …]), sémantique différente de la recherche par valeur.
    def ref?(col_type)
      col_type.to_s.start_with?(REF_PREFIX)
    end

    def encode_key(value, col_type)
      return value unless ref?(col_type)
      return value if encoded?(value)

      [LOOKUP_MARKER, value]
    end

    def encoded?(value)
      value.is_a?(Array) && value.first == LOOKUP_MARKER
    end
  end
end
