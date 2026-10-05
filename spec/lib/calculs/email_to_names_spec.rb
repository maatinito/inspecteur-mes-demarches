# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Calculs::EmailToNames do
  let(:calcul) { described_class.new({ 'mails' => { 'keanu.maraetetoa' => 'Keanu,MARAETETOA,Technicien zoosanitaire' } }) }
  let(:instructeurs) { [] }
  let(:dossier) { double('dossier', instructeurs:, annotations: []) }

  subject do
    result = {}
    calcul.process_row(dossier, result)
    result
  end

  def instructeur(email) = double('instructeur', email:)

  context 'with several instructeurs following the dossier' do
    let(:instructeurs) { [instructeur('caroline.duflocq@administration.gov.pf'), instructeur('keanu.maraetetoa@administration.gov.pf')] }

    it 'keeps the first one as Instructeur' do
      expect(subject['Instructeur.prénom']).to eq 'Caroline'
      expect(subject['Instructeur.nom']).to eq 'Duflocq'
    end

    it 'exposes the last one as Dernier instructeur, resolved through the mails table' do
      expect(subject['Dernier instructeur.prénom']).to eq 'Keanu'
      expect(subject['Dernier instructeur.nom']).to eq 'MARAETETOA'
      expect(subject['Dernier instructeur.fonction']).to eq 'Technicien zoosanitaire'
    end
  end

  context 'with a single instructeur' do
    let(:instructeurs) { [instructeur('keanu.maraetetoa@administration.gov.pf')] }

    it 'gives the same person for both variables' do
      expect(subject['Instructeur.nom']).to eq 'MARAETETOA'
      expect(subject['Dernier instructeur.nom']).to eq 'MARAETETOA'
    end
  end

  context 'without instructeur' do
    it 'defines neither variable' do
      expect(subject.keys.grep(/instructeur/i)).to be_empty
    end
  end
end
