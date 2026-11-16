# frozen_string_literal: true

module Referentiel
  # Référence d'une pièce jointe Mes-Démarches stockée dans une table DLNUF à la place du
  # fichier : `md:<numero_dossier>:<stable_id>` ou, dans un bloc répétable,
  # `md:<numero_dossier>:<stable_id>:<row_id>`.
  #
  # L'identifiant GraphQL d'un champ est le Base64 de `Champ-<stable_id>` ou
  # `Champ-<stable_id>|<row_id>` (Champ#to_typed_id côté Mes-Démarches).
  module ReferencePj
    IDENTIFIANT = /\AChamp-(\d+)(?:\|([A-Za-z0-9_-]+))?\z/

    # @return [String, nil] nil si le champ n'a aucun fichier
    # @raise [ArgumentError] si l'identifiant du champ n'a pas la forme attendue
    def self.pour(numero_dossier, champ)
      return nil if champ.files.blank?

      stable_id, row_id = decoder(champ.id)
      ['md', numero_dossier, stable_id, row_id].compact.join(':')
    end

    # stable_id entier d'un champ ou d'un descripteur de champ (même encodage `Champ-<stable_id>`).
    # @raise [ArgumentError] si l'identifiant n'a pas la forme attendue
    def self.stable_id(champ)
      decoder(champ.id).first.to_i
    end

    def self.decoder(identifiant)
      clair = decoder_base64(identifiant.to_s)
      correspondance = IDENTIFIANT.match(clair) or
        raise ArgumentError, "identifiant de champ inattendu : #{clair.inspect}"
      [correspondance[1], correspondance[2]]
    end

    # Tolère alphabet standard ou URL-safe, avec ou sans remplissage « = ».
    def self.decoder_base64(identifiant)
      brut = identifiant.delete('=').tr('+/', '-_')
      Base64.urlsafe_decode64(brut + ('=' * ((4 - (brut.length % 4)) % 4))).force_encoding(Encoding::UTF_8)
    end
    private_class_method :decoder, :decoder_base64
  end
end
