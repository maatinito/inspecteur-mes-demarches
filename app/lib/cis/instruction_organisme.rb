# frozen_string_literal: true

module Cis
  class InstructionOrganisme < Instruction
    def version
      super + 8
    end

    def required_fields
      super + %i[champ_etat_nominatif]
    end

    def check(dossier)
      candidats = candidats(dossier)
      previous_candidats = candidats.deep_dup
      update_candidats(candidats, dossier)
      set_candidats_attribute(dossier, params[:champ_candidats], candidats.values) if previous_candidats != candidats
      set_text_attribute(dossier, params[:champ_synthese], synthese(candidats))
    end

    private

    DN = 'Numéro DN'
    MAPPING = { 'Nom de famille' => 'Nom', 'Prénom(s)' => 'Prénom' }.freeze

    def update_candidats_bloc(candidats, champ_etat)
      champs = champ_etat.champs
      bloc = {}
      champs.each do |champ|
        if bloc[champ.label].present?
          # process current bloc
          save_candidat(candidats, bloc)
          bloc = {} # starts a new block
        end
        case champ.label
        when 'Numéro DN'
          bloc['Numéro DN'] = champ.numero_dn.to_i
          bloc['Date de naissance'] = Date.iso8601(champ.date_de_naissance)
        when 'Suite'
          nil
        else
          name = MAPPING.fetch(champ.label, champ.label)
          bloc[name] = champ.value
        end
      end
      save_candidat(candidats, bloc)
    end

    def save_candidat(candidats, bloc)
      dn = bloc['Numéro DN']
      candidats[dn] = candidats[dn]&.merge(bloc) || bloc
      add_presence(candidats[dn])
    end

    HEADER_REGEXPS = ['Civilité', 'Nom', 'Prénom', 'Numéro DN', 'Date de naissance', 'Activité']
                     .to_h { |c| [c, Regexp.new(Regexp.quote(c), 'i')] }.freeze

    def update_candidats_excel(candidats, champ_etat)
      file = champ_etat.file
      return {} unless file.present?

      filename = file.filename
      url = file.url
      extension = File.extname(filename)
      return {} if bad_extension(extension)

      download(url, extension) do |xlsx_file|
        xlsx = Roo::Spreadsheet.open(xlsx_file)
        xlsx.sheet(0).each(HEADER_REGEXPS) do |row|
          save_candidat(candidats, row) if row['Civilité'] != 'Civilité'
        end
      rescue Roo::HeaderRowNotFoundError => e
        columns = e.message.gsub(%r{[/\[\]]}, '')
        throw "Colonne(s) manquante(s) dans les données d'instruction: #{columns}"
      end
    end

    def add_presence(row)
      row[PRESENCE] = case row[PRESENCE]
                      when 'OA', 'OA+DE'
                        row[PRESENCE]
                      when 'DE'
                        'OA+DE'
                      when nil, ''
                        'OA'
                      end
    end

    def update_candidats(candidats, dossier)
      champ_etat = dossier_field(dossier, @params[:champ_etat_nominatif])
      case champ_etat.__typename
      when 'RepetitionChamp'
        update_candidats_bloc(candidats, champ_etat)
      when 'PieceJustificativeChamp'
        update_candidats_excel(candidats, champ_etat)
      end
    end
  end
end
