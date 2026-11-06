# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe TeFenuaParcelles do
  let(:controle) do
    described_class.new(champ: 'Parcelle(s) cultivée(s)', bloc_destination: 'Parcelles cultivées',
                        champs_infos: { 'Surface (en m²)' => 'Surface (en m²)', 'Ile' => 'Ile' })
  end

  # Parcelle RH30 de Moorea, telle que l'API la renvoie
  let(:rh30_coordinates) do
    [[[[-149.90919155, -17.49422045], [-149.90906289, -17.49455553], [-149.90947129, -17.49473337],
       [-149.90994236, -17.49484041], [-149.91015976, -17.49485428], [-149.91027528, -17.49476933],
       [-149.91044601, -17.49415236], [-149.90996198, -17.49369255], [-149.90979738, -17.49360892],
       [-149.90946637, -17.49349838], [-149.90919155, -17.49422045]]]]
  end
  let(:rh30) do
    double('GeoArea', geometry: double('GeoJSON', type: 'MultiPolygon', coordinates: rh30_coordinates),
                      section: 'RH', numero: '30', commune: 'MOOREA MAIAO', commune_associee: 'HAAPITI', ile: 'Moorea')
  end
  let(:info_texte) { "Surface (en m²): 14457\nSection: RH\nNuméro: 30\nIle: Moorea\nSource des données: https://www.tefenua.data.gov.pf" }
  let(:tefenua_body) do
    { type: 'FeatureCollection',
      features: [{ properties: { id: 122_137, label: 'RH30', info_titre: 'Parcelle RH30 (MOOREA-MAIAO)', info_texte: } }] }.to_json
  end

  def row(titre = nil, surface = nil, ile = nil)
    double('Row', champs: [
             double('Champ', id: SecureRandom.hex(4), label: 'Parcelle', __typename: 'TextChamp', value: titre),
             double('Champ', id: SecureRandom.hex(4), label: 'Surface (en m²)', __typename: 'TextChamp', value: surface),
             double('Champ', id: SecureRandom.hex(4), label: 'Ile', __typename: 'TextChamp', value: ile)
           ])
  end

  describe '#point_interieur' do
    it 'returns a point inside the parcel' do
      lon, lat = controle.send(:point_interieur, rh30.geometry)
      expect(lon).to be_between(-149.9105, -149.9090)
      expect(lat).to be_between(-17.4949, -17.4934)
    end

    it 'stays inside a concave (U-shaped) polygon whose centroid is outside' do
      u = [[[0, 0], [3, 0], [3, 3], [2, 3], [2, 1], [1, 1], [1, 3], [0, 3], [0, 0]]]
      x, y = controle.send(:point_interieur, double(type: 'Polygon', coordinates: u))
      expect(y).to eq(1.5)
      expect(x).to be_between(0, 1)
    end
  end

  describe '#infos' do
    before { controle.dossier = double('Dossier', number: 1) }

    it 'uses the Te Fenua titre and texte' do
      stub_request(:get, /tefenua.gov.pf/).to_return(status: 200, body: tefenua_body)
      expect(controle.send(:infos, rh30)).to eq(
        titre: 'Parcelle RH30 (MOOREA-MAIAO)', texte: info_texte,
        infos: { 'Surface (en m²)' => '14457', 'Section' => 'RH', 'Numéro' => '30', 'Ile' => 'Moorea',
                 'Source des données' => 'https://www.tefenua.data.gov.pf' }
      )
    end

    it 'falls back to the API data when Te Fenua is unavailable' do
      stub_request(:get, /tefenua.gov.pf/).to_return(status: 503)
      expect(controle.send(:infos, rh30)).to eq(
        titre: 'Parcelle RH30 (MOOREA MAIAO)',
        texte: "Section: RH\nNuméro: 30\nIle: Moorea\nCommune: MOOREA MAIAO\nCommune associée: HAAPITI",
        infos: { 'Section' => 'RH', 'Numéro' => '30', 'Ile' => 'Moorea', 'Commune' => 'MOOREA MAIAO', 'Commune associée' => 'HAAPITI' }
      )
    end

    it 'falls back when Te Fenua returns another parcel' do
      stub_request(:get, /tefenua.gov.pf/).to_return(status: 200, body: tefenua_body.sub('"RH30"', '"RH31"'))
      expect(controle.send(:infos, rh30)[:titre]).to eq('Parcelle RH30 (MOOREA MAIAO)')
    end
  end

  describe '#process' do
    let(:demarche) { double('Demarche', instructeur: 'instructeur') }
    let(:te_fenua) { double('Champ', __typename: 'TeFenuaChamp', label: 'Parcelle(s) cultivée(s)', geo_areas: [rh30, rh30]) }
    let(:dossier) { double('Dossier', id: 'D1', number: 1, state: 'en_construction', champs: [te_fenua], annotations: [bloc]) }
    let(:rows) { [row('Parcelle RH30 (MOOREA-MAIAO)', '14457', 'Moorea'), row('ancienne', '1', 'Moorea')] }
    let(:bloc) { double('Bloc', label: 'Parcelles cultivées', rows:) }

    before do
      stub_request(:get, /tefenua.gov.pf/).to_return(status: 200, body: tefenua_body)
      allow(SetAnnotationValue).to receive(:allocate_blocks).and_return(bloc)
      allow(SetAnnotationValue).to receive(:raw_set_value)
    end

    it 'writes one row per distinct parcel and only changed values' do
      rh31 = double('GeoArea', geometry: rh30.geometry, section: 'RH', numero: '31', commune: 'MOOREA MAIAO',
                               commune_associee: 'HAAPITI', ile: 'Moorea')
      allow(te_fenua).to receive(:geo_areas).and_return([rh30, rh31, rh30])
      controle.process(demarche, dossier)
      expect(SetAnnotationValue).to have_received(:allocate_blocks).with(dossier, 'instructeur', 'Parcelles cultivées', 2)
      expect(SetAnnotationValue).to have_received(:raw_set_value).twice
      expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', rows[1].champs[0].id, 'Parcelle RH31 (MOOREA MAIAO)')
      expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', rows[1].champs[1].id, '')
      expect(controle.dossier_updated?).to be true
    end

    it 'clears the rows of deselected parcels, a parcel selected twice counting once' do
      controle.process(demarche, dossier)
      expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', rows[1].champs[0].id, '')
      expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', rows[1].champs[1].id, '')
      expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', rows[1].champs[2].id, '')
    end

    it 'also writes the full Te Fenua text when champ_texte is set' do
      controle.params[:champ_texte] = 'Informations'
      rows[0].champs << double('Champ', id: 'info', label: 'Informations', __typename: 'TextareaChamp', value: nil)
      controle.process(demarche, dossier)
      expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', 'info', info_texte)
    end

    it 'writes a summary of the parcel when composition is set, omitting missing parts' do
      controle.params[:composition] = ['{titre}', '{Surface (en m²)} m²', '{Archipel}', '{Ile}']
      allow(te_fenua).to receive(:geo_areas).and_return([rh30])
      controle.process(demarche, dossier)
      expect(SetAnnotationValue).to have_received(:raw_set_value)
        .with('D1', 'instructeur', rows[0].champs[0].id, 'Parcelle RH30 (MOOREA-MAIAO) - 14457 m² - Moorea')
    end

    it 'does nothing when nothing changed' do
      rows.pop
      controle.process(demarche, dossier)
      expect(SetAnnotationValue).not_to have_received(:raw_set_value)
      expect(controle.dossier_updated?).to be false
    end
  end
end
# rubocop:enable Metrics/BlockLength
