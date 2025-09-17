# frozen_string_literal: true

module Cis
  class EtatPrevisionnelV2Check < EtatPrevisionnelCheck
    include Shared

    def version
      super + 4
    end

    def required_fields
      super + %i[message_iban message_telephone]
    end

    COLUMNS = ['Civilité', 'Nom', 'Prénom(s)', 'Numéro DN', 'Date de naissance', 'Téléphone', 'IBAN', "Niveau d'études",
               'Date de naissance du conjoint', 'Numéro DN du conjoint', "Nombre d'enfants", 'Activité']
              .to_h { |c| [c, Regexp.new(Regexp.quote(c), 'i')] }.freeze

    CHECKS = %i[format_dn nom prenoms empty_columns employee_age iban telephone format_dn_conjoint].freeze

    REQUIRED_COLUMNS = ['Nom', 'Prénom(s)', 'Numéro DN', 'Civilité', 'IBAN', 'Activité'].freeze

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
        when 'TextChamp', 'CiviliteChamp', 'DecimalNumberChamp', 'CheckbowChamp'
          bloc[champ.label] = champ.value unless champ.value.nil?
        when 'IntegerNumberChamp'
          bloc[champ.label] = champ.value.to_i unless champ.value.nil?
        end
      end
      rows << bloc
    end

    def check_iban?(line)
      IBANTools::IBAN.valid?(line['IBAN'])
    end

    def check_telephone?(line)
      phone = line['Téléphone']
      phone.blank? || Phonelib.valid_for_country?(phone, :PF)
    end
  end
end
