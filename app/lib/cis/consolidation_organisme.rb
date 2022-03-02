# frozen_string_literal: true

module Cis
  class ConsolidationOrganisme < Consolidation
    def version
      super + 9
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
      bloc[ROME] = code_rome(bloc[ACTIVITE])
      dn = bloc['Numéro DN']
      candidats[dn] = candidats[dn]&.merge(bloc) || bloc
      add_presence(candidats[dn])
    end

    CODES_ROMES = {
      'Accueil et d’information' => 'M1601',
      'Aide agricole et horticole' => 'A1402',
      'Aide-livreur' => 'N4105',
      'Animation culturelles et sportives' => 'G1202',
      'Assistance auprès de personnes' => 'K1302',
      'Assistant de vie scolaire' => 'K2104',
      'Autres' => '',
      'Bâtiments (Maintenance)' => 'I1203',
      'Cuisine' => 'G1602',
      'Enquêteur' => 'M1401',
      'Espaces verts et jardins' => 'A1203',
      'Habillement (confection)' => 'B1803',
      'Menuisier' => 'H2206',
      'Mécanicien' => 'I1604',
      'Médiation et proximité' => 'K1204',
      'Propreté des locaux' => 'K2204',
      'Propreté urbaine' => 'K2303',
      'Secrétariat et administration' => 'M1602'
    }.freeze

    def code_rome(activity)
      CODES_ROMES[activity] || 'Inconnu'
    end

    HEADER_REGEXPS = ['Civilité', 'Nom', 'Prénom', 'Numéro DN', 'Date de naissance', 'Activité']
                     .to_h { |c| [c, Regexp.new(Regexp.quote(c), 'i')] }.freeze

    def update_candidats_excel(candidats, champ_etat)
      file = champ_etat.file
      return {} unless file.present?

      return {} if bad_extension(File.extname(file.filename))

      PieceJustificativeCache.get(file) do |xlsx_file|
        xlsx = Roo::Spreadsheet.open(xlsx_file)
        xlsx.sheet(0).each(HEADER_REGEXPS) do |row|
          save_candidat(candidats, row) if row['Civilité'] != 'Civilité'
        end
      rescue Roo::HeaderRowNotFoundError => e
        columns = e.message.gsub(%r{[/\[\]]}, '')
        throw "Colonne(s) manquante(s) dans les données d'Consolidation: #{columns}"
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
