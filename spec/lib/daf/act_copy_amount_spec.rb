# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Daf::ActCopyAmount do
  let(:dossier_nb) { 303_082 }
  let(:dossier) do
    r = nil
    DossierActions.on_dossier(dossier_nb) { |d| r = d }
    r
  end
  let(:demarche) { double(Demarche) }
  let(:controle) { FactoryBot.build :act_copy_amount }
  let(:instructeur) { 'instructeur' }

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'dossier ready with different answers', vcr: { cassette_name: 'daf_act_copy_amount_1' } do
    let(:amount) { 300 + 660 + 0 }
    it 'amount should be set' do
      allow(demarche).to receive(:instructeur).and_return(instructeur)
      expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_montant], amount)
      subject
    end
  end

  context 'dossier not ready ', vcr: { cassette_name: 'daf_act_copy_amount_1' } do
    it 'amount should not be set' do
      allow(demarche).to receive(:instructeur).and_return(instructeur)
      field = controle.dossier_annotations(dossier, controle.params[:champ_commande_prete]).first
      expect(field).to receive(:value).and_return(false)
      expect(SetAnnotationValue).not_to receive(:set_value)
      subject
    end
  end

  context 'dossier ready but amount already set', vcr: { cassette_name: 'daf_act_copy_amount_1' } do
    it 'amount should not be set' do
      allow(demarche).to receive(:instructeur).and_return(instructeur)
      field = controle.dossier_annotations(dossier, controle.params[:champ_montant]).first
      expect(field).to receive(:value).and_return(100)
      expect(SetAnnotationValue).not_to receive(:set_value)
      subject
    end
  end
end
