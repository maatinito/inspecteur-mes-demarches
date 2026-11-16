# frozen_string_literal: true

module Referentiel
  # Fige le type d'une table (archive ou DLNUF) à sa première lecture et refuse toute
  # modification ultérieure du marqueur, pour ne jamais effacer ou copier sur une table dont
  # le contrat a changé.
  module Verrou
    class Refus < StandardError
      attr_reader :table

      def initialize(message, table = nil)
        super(message)
        @table = table
      end
    end

    # Avec un bloc, `yield(mode, table)` est appelé une fois le marqueur reconnu conforme à
    # l'enregistrement (ou la table adoptée), AVANT l'effacement de refus_depuis / alerte_le :
    # un refus levé par le bloc (via `refuser!`) garde donc ses dates et l'alerte reste limitée.
    # Marqueur illisible sans enregistrement : la table est enregistrée en mode `inconnu` (pour
    # dater le refus et limiter l'alerte), jamais figée en archive. Le type est figé à la première
    # lecture lisible, comme pour une table jamais vue.
    def self.mode!(backend:, table_ref:, description_primaire:, lignes:, &controle)
      table = ReferentielTable.find_by(backend:, table_ref: table_ref.to_s)
      type_lu = Marqueur.type_table(description_primaire)

      if type_lu == :invalid
        table ||= ReferentielTable.create!(backend:, table_ref: table_ref.to_s, mode: 'inconnu')
        refuser!(table, 'marqueur illisible', type_lu)
      end

      if table.nil? || table.inconnu?
        adopter!(table || ReferentielTable.new(backend:, table_ref: table_ref.to_s), type_lu, lignes, &controle)
      else
        verifier!(table, type_lu, &controle)
      end
    end

    def self.adopter!(table, type_lu, lignes)
      type, proprietaire = type_lu
      table.update!(mode: type.to_s, proprietaire:)
      if type == :dlnuf
        nombre = lignes.call.to_i
        Alerte.informer(table, "table #{table.table_ref} adoptée en DLNUF, #{nombre} lignes déjà présentes") if nombre.positive?
      end
      yield(type, table) if block_given?
      effacer_refus(table)
      type
    end
    private_class_method :adopter!

    def self.verifier!(table, type_lu)
      type, proprietaire = type_lu
      conforme = (table.mode == 'archive' && type == :archive) ||
                 (table.dlnuf? && type == :dlnuf && table.proprietaire == proprietaire)
      refuser!(table, 'type ou propriétaire modifié', type_lu) unless conforme

      yield(type, table) if block_given?
      effacer_refus(table)
      type
    end
    private_class_method :verifier!

    def self.effacer_refus(table)
      table.update_columns(refus_depuis: nil, alerte_le: nil) if table.refus_depuis || table.alerte_le
    end
    private_class_method :effacer_refus

    # Date le premier refus (conservée aux suivants) et lève Refus.
    def self.refuser!(table, raison, type_lu = nil)
      table.update_columns(refus_depuis: Time.current) if table.refus_depuis.nil?
      lu_texte = if type_lu.nil? then nil
                 elsif type_lu == :invalid then ', lu : illisible'
                 else ", lu : #{type_lu.compact.join('/')}"
                 end
      raise Refus.new("Référentiel #{table.backend} table #{table.table_ref} : #{raison} " \
                      "(enregistré : #{table.mode}#{lu_texte}, refus depuis #{table.refus_depuis}).", table)
    end
  end
end
