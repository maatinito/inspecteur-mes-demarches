# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe CulturesParFamille do
  let(:controle) do
    described_class.new(champ: 'Cultures sur ces parcelles', bloc_destination: 'Cultures par famille',
                        familles: { 'Bananiers/fei': ['banane fei', 'fei'], Vanille: ['vanille'],
                                    'Cultures maraîchères et horticoles': ['tomate', 'pépinière maraichère, aromatique'] })
  end
  let(:demarche) { double('Demarche', instructeur: 'instructeur') }
  let(:source) do
    double('Champ', __typename: 'MultipleDropDownListChamp', label: 'Cultures sur ces parcelles',
                    string_value: 'vanille, tomate, banane fei, pépinière maraichère, aromatique, kava')
  end
  let(:dossier) { double('Dossier', id: 'D1', number: 1, state: 'en_construction', champs: [source], annotations: [bloc]) }
  let(:rows) { [row('Vanille', 'vanille'), row('ancienne', 'x')] }
  let(:bloc) { double('Bloc', label: 'Cultures par famille', rows:) }

  def row(famille = nil, cultures = nil)
    double('Row', champs: [
             double('Champ', id: SecureRandom.hex(4), label: 'Famille', __typename: 'TextChamp', value: famille),
             double('Champ', id: SecureRandom.hex(4), label: 'Cultures', __typename: 'TextChamp', value: cultures)
           ])
  end

  before do
    allow(SetAnnotationValue).to receive(:allocate_blocks).and_return(bloc)
    allow(SetAnnotationValue).to receive(:raw_set_value)
  end

  def ecrit?(row, colonne, valeur)
    expect(SetAnnotationValue).to have_received(:raw_set_value).with('D1', 'instructeur', rows[row].champs[colonne].id, valeur)
  end

  it 'writes one row per family, in the order of the configuration' do
    rows.push(row, row)
    controle.process(demarche, dossier)
    expect(SetAnnotationValue).to have_received(:allocate_blocks).with(dossier, 'instructeur', 'Cultures par famille', 4)
    ecrit?(0, 0, 'Bananiers/fei')
    ecrit?(0, 1, 'banane fei')
    ecrit?(1, 0, 'Vanille')
    ecrit?(1, 1, 'vanille')
    ecrit?(2, 0, 'Cultures maraîchères et horticoles')
    ecrit?(2, 1, 'tomate, pépinière maraichère, aromatique')
    ecrit?(3, 0, 'Autres')
    ecrit?(3, 1, 'kava')
    expect(SetAnnotationValue).to have_received(:raw_set_value).exactly(8).times
    expect(controle.dossier_updated?).to be true
  end

  it 'clears the rows of families no longer selected' do
    allow(source).to receive(:string_value).and_return('vanille')
    controle.process(demarche, dossier)
    ecrit?(1, 0, '')
    ecrit?(1, 1, '')
  end

  it 'does nothing when nothing changed' do
    allow(source).to receive(:string_value).and_return('vanille')
    rows.pop
    controle.process(demarche, dossier)
    expect(SetAnnotationValue).not_to have_received(:raw_set_value)
    expect(controle.dossier_updated?).to be false
  end

  context 'with Détail culture' do
    let(:controle) do
      described_class.new(champ: 'Cultures sur ces parcelles', bloc_destination: 'Cultures par famille', bloc_detail: 'Détail culture',
                          familles: { Vanille: ['vanille'], 'Cultures maraîchères et horticoles': %w[tomate poivron] })
    end
    let(:surface) { 500 }
    let(:surface_bio) { 100 }
    let(:lignes_detail) { [['tomate', 75, 'Non bio'], ['vanille', 100, 'Bio']] }
    let(:detail) { double('Bloc', label: 'Détail culture', __typename: 'RepetitionChamp', rows: lignes_detail.map { |l| ligne_detail(*l) }) }
    let(:dossier) do
      double('Dossier', id: 'D1', number: 1, state: 'en_construction', annotations: [bloc],
                        champs: [source, detail, entier('Surface cultivée', surface), entier('Surface cultivée en bio', surface_bio)])
    end
    let(:rows) { [row, row, row] }
    let(:ecrit) { {} }

    before do
      allow(SetAnnotationValue).to receive(:raw_set_value) { |_, _, id, valeur| ecrit[id] = valeur }
    end

    def entier(label, valeur)
      double('Champ', label:, __typename: 'IntegerNumberChamp', int_value: valeur)
    end

    def liste(label, valeur)
      double('Champ', label:, __typename: 'DropDownListChamp', string_value: valeur, value: valeur)
    end

    def ligne_detail(culture, surface, bio = nil)
      double('Row', champs: [liste('Culture', culture), entier('Surface (m²)', surface), liste('Bio / non bio', bio)])
    end

    # [[famille, cultures]] des lignes écrites
    def resultat
      rows.map { |r| r.champs.map { |c| ecrit[c.id] } }.reject { |l| l.all?(&:blank?) }
    end

    it 'uses the detail block in priority' do
      controle.process(demarche, dossier)
      expect(resultat).to eq([['Vanille', 'vanille (100 m² bio)'], ['Cultures maraîchères et horticoles', 'tomate (75 m² non bio)']])
    end

    context 'when no surface is in bio' do
      let(:lignes_detail) { [['tomate', 75]] }

      [nil, 0].each do |valeur|
        it "writes non bio (surface bio #{valeur.inspect})" do
          allow(dossier).to receive(:champs).and_return([detail, entier('Surface cultivée', 500), entier('Surface cultivée en bio', valeur)])
          controle.process(demarche, dossier)
          expect(resultat).to eq([['Cultures maraîchères et horticoles', 'tomate (75 m² non bio)']])
        end
      end
    end

    context 'when the whole surface is in bio' do
      let(:lignes_detail) { [['tomate', 75, 'Non bio']] }

      [500, 600].each do |valeur|
        it "writes bio (surface bio #{valeur})" do
          allow(dossier).to receive(:champs).and_return([detail, entier('Surface cultivée', 500), entier('Surface cultivée en bio', valeur)])
          controle.process(demarche, dossier)
          expect(resultat).to eq([['Cultures maraîchères et horticoles', 'tomate (75 m² bio)']])
        end
      end
    end

    context 'with a crop grown bio and non bio' do
      let(:lignes_detail) { [['tomate', 75, 'Bio'], ['tomate', 50, 'Non bio']] }

      it 'keeps both rows' do
        controle.process(demarche, dossier)
        expect(resultat).to eq([['Cultures maraîchères et horticoles', 'tomate (75 m² bio), tomate (50 m² non bio)']])
      end
    end

    context 'with missing answers' do
      let(:lignes_detail) { [['tomate', 75], ['poivron', nil, 'Bio'], [nil, 20, 'Bio']] }

      it 'omits what is missing and ignores rows without crop' do
        controle.process(demarche, dossier)
        expect(resultat).to eq([['Cultures maraîchères et horticoles', 'tomate (75 m²), poivron']])
      end
    end

    context 'when the detail block is empty' do
      let(:lignes_detail) { [] }

      it 'falls back to the old list' do
        controle.process(demarche, dossier)
        expect(resultat).to eq([['Vanille', 'vanille'], ['Cultures maraîchères et horticoles', 'tomate'],
                                ['Autres', 'banane fei, pépinière maraichère, aromatique, kava']])
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
