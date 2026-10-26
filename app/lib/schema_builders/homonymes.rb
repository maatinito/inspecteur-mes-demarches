# frozen_string_literal: true

module SchemaBuilders
  # Champs d'une démarche (ou d'un bloc) portant le même libellé : ils
  # visent la même colonne cible, que le diff, le constructeur et la synchro
  # rapprochent par libellé. Règle commune : seul le PREMIER champ d'un libellé
  # (hors types ignorés) est retenu.
  #
  # Le constructeur doit l'appliquer AVANT les exclusions : le diff n'affiche
  # que le premier champ, et décocher celui-ci doit exclure la colonne, pas
  # laisser passer l'homonyme suivant (cas 3135 : « Extrait du cadastre » en
  # Oui/Non puis en pièce jointe).
  module Homonymes
    module_function

    # Descripteurs synchronisables, un seul par libellé (le premier).
    def retenus(descriptors, type_mapper)
      synchronisables(descriptors, type_mapper).uniq(&:label)
    end

    # Libellés partagés : [{ label:, retenu: typename, ecartes: [typename…] }].
    def groupes(descriptors, type_mapper)
      synchronisables(descriptors, type_mapper).group_by(&:label).filter_map do |label, champs|
        next if champs.size < 2

        { label: label, retenu: champs.first.__typename.to_s, ecartes: champs.drop(1).map { |c| c.__typename.to_s } }
      end
    end

    def synchronisables(descriptors, type_mapper)
      Array(descriptors).reject do |descriptor|
        typename = descriptor.__typename.to_s
        TypeMapper.should_ignore_type?(typename) || !type_mapper.supported_type?(typename)
      end
    end
  end
end
