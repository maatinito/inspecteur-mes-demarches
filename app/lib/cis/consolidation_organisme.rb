# frozen_string_literal: true

module Cis
  class ConsolidationOrganisme < Consolidation
    def version
      super + 18
    end

    def required_fields
      super + %i[champ_etat_nominatif]
    end

    def check(dossier)
      candidats = candidats(dossier)
      previous_candidats = candidats.deep_dup
      update_candidats(candidats, dossier)
      return unless previous_candidats != candidats

      set_candidats_attribute(dossier, params[:champ_candidats], candidats.values)
    end

    private

    DN = 'Numéro DN'
    # MAPPING = { 'Téléphone du stagiaire' => 'Téléphone' }.freeze

    def update_candidats_bloc(candidats, champ_etat)
      champs = champ_etat.champs
      bloc = {}
      champs.each do |champ|
        if bloc[champ.label].present?
          # process current bloc
          save_candidat(candidats, bloc)
          bloc = {} # starts a new block
        end
        store_value(bloc, champ)
      end
      save_candidat(candidats, bloc)
    end

    def store_value(bloc, champ)
      return if champ.label == 'Suite'

      case champ.__typename
      when 'NumeroDnChamp'
        if champ.numero_dn.present?
          bloc[champ.label] = champ.numero_dn.to_i
          bloc[champ.label.gsub(/Num[eé]ro DN/i, 'Date de naissance')] = Date.iso8601(champ.date_de_naissance)
        end
      when 'TextChamp'
        bloc[champ.label] = if champ.value.nil?
                              ''
                            elsif /^[-+]?[0-9]+$/.match?(champ.value)
                              champ.value.to_i
                            else
                              champ.value
                            end
      when 'CiviliteChamp', 'CheckbowChamp'
        bloc[champ.label] = champ.value
      when 'IntegerNumberChamp'
        bloc[champ.label] = champ.value.to_i
      when 'DecimalNumberChamp'
        bloc[champ.label] = champ.value.to_f
      end
    end

    def save_candidat(candidats, bloc)
      bloc[ROME] = code_rome(bloc[ACTIVITE])
      bloc[AIDE] = 50_000
      dn = bloc['Numéro DN']
      candidats[dn] = candidats[dn]&.merge(bloc) || bloc
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

    HEADER_REGEXPS = COLUMN_REGEXPS.except(ROME, AIDE)

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
        throw "Colonne(s) manquante(s) dans #{champ_etat.label} sur dossier #{@dossier.number}: #{columns}"
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
