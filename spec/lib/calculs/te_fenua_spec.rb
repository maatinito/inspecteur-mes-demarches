# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calculs::TeFenua do
  let(:calcul) { described_class.new({ 'champ' => "Adresse du lieu d'isolement" }) }
  let(:geo) do
    { markers: { type: 'FeatureCollection',
                 features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: [-149.578, -17.544] },
                              properties: { commune: 'PAPEETE', ile: 'Tahiti', section: 'AB', numero: '5' } }] } }.to_json
  end
  let(:valeur) { geo }
  let(:dossier) do
    double('Dossier', champs: [double('Carte', label: "Adresse du lieu d'isolement", __typename: 'TeFenuaChamp',
                                               string_value: valeur)], annotations: [])
  end

  subject { {}.tap { |output| calcul.process_row(dossier, output) } }

  it 'décrit le lieu par commune, île et parcelle' do
    expect(subject["Adresse du lieu d'isolement.lieu"]).to eq 'PAPEETE (Tahiti), parcelle AB 5'
    expect(subject["Adresse du lieu d'isolement.commune"]).to eq 'PAPEETE'
    expect(subject["Adresse du lieu d'isolement.parcelle"]).to eq 'AB 5'
  end

  context 'sans parcelle' do
    let(:valeur) { geo.sub('"section":"AB","numero":"5"', '"section":null,"numero":null') }

    it 'garde commune et île' do
      expect(subject["Adresse du lieu d'isolement.lieu"]).to eq 'PAPEETE (Tahiti)'
    end
  end

  [nil, '', '{"markers":{"features":[]}}', 'pas du json', '[]', '{"markers":[]}', 'null', '123', '"x"',
   '{"markers":{"features":[{"properties":"x"}]}}'].each do |vide|
    context "avec la valeur #{vide.inspect}" do
      let(:valeur) { vide }

      it 'rend des chaînes vides sans lever' do
        expect(subject["Adresse du lieu d'isolement.lieu"]).to eq ''
      end
    end
  end

  it 'exige le paramètre champ' do
    expect(described_class.new({}).errors.join).to include('champ')
  end
end
