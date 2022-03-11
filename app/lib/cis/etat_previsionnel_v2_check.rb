# frozen_string_literal: true

module Cis
  class EtatPrevisionnelV2Check < EtatPrevisionnelCheck
    include Shared

    def version
      super + 2
    end

    COLUMNS = ['Civilité', 'Nom', 'Prénom(s)', 'Numéro DN', 'Date de naissance', 'Activité']
      .to_h { |c| [c, Regexp.new(Regexp.quote(c), 'i')] }.freeze

    CHECKS = %i[format_dn nom prenoms empty_columns employee_age].freeze

    REQUIRED_COLUMNS = ['Nom', 'Prénom(s)', 'Numéro DN', 'Civilité', 'Activité'].freeze

    def sheets_to_control
      ['Stagiaires']
    end

    def check(dossier)
      champ_etat = dossier_field(dossier, @params[:champ])
      case champ_etat.__typename
      when 'RepetitionChamp'
        cis_count = check_repetition(champ_etat)
        check_cis_demandes(cis_count)
      when 'PieceJustificativeChamp'
        super
      end
    end

    private

    def id_of(row)
      "#{row['Nom']} #{row['Prénom(s)']}"
    end

    def check_repetition(champ)
      rows = repetition_rows(champ)
      apply_checks(self.class::CHECKS, champ.label, rows)
      rows.size
    end

    def repetition_rows(root_champ)
      rows = []
      champs = root_champ.champs
      bloc = {}
      champs.each do |champ|
        if bloc[champ.label].present?
          rows << bloc
          bloc = {} # starts a new block
        end
        case champ.__typename
        when 'NumeroDnChamp'
          if champ.numero_dn.present?
            bloc[champ.label] = champ.numero_dn.to_i
            bloc[champ.label.gsub(/Num[eé]ro DN/i, 'Date de naissance')] = Date.iso8601(champ.date_de_naissance)
          end
        when 'TextChamp', 'CiviliteChamp', 'IntegerNumberChamp', 'DecimalNumberChamp', 'CheckbowChamp'
          bloc[champ.label] = champ.value unless champ.value.nil?
        when 'IntegerNumberChamp'
          bloc[champ.label] = champ.value.to_i unless champ.value.nil?
        end
      end
      rows << bloc
    end
  end
end
