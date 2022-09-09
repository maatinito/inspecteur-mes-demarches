# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Daf::ActCopyAmount do
  let(:dossier_nb) { 308_712 }
  let(:dossier) { DossierActions.on_dossier(dossier_nb) }
  let(:demarche) do
    demarche = double(Demarche)
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    demarche
  end

  let(:controle) { FactoryBot.build :act_copy_amount }
  let(:instructeur) { 'instructeur' }
  let(:amount) { 300 + 660 + 0 }

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'dossier ready with different answers', vcr: { cassette_name: 'daf_act_copy_amount_1' } do
    it 'amount should be set' do
      expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_montant_theorique], amount)
      expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_montant], amount)
      subject
    end
  end

  context 'dossier not ready ', vcr: { cassette_name: 'daf_act_copy_amount_2' } do
    it 'amount should not be set' do
      field = controle.dossier_annotations(dossier, controle.params[:champ_commande_prete]).first
      expect(field).to receive(:value).and_return(false)
      expect(SetAnnotationValue).not_to receive(:set_value)
      subject
    end
  end

  context 'dossier ready but amounts already set', vcr: { cassette_name: 'daf_act_copy_amount_2' } do
    it 'amount should not be set' do
      field = controle.dossier_annotations(dossier, controle.params[:champ_montant_theorique]).first
      expect(field).to receive(:value).and_return(100)
      field = controle.dossier_annotations(dossier, controle.params[:champ_montant]).first
      expect(field).to receive(:value).and_return(100)
      expect(SetAnnotationValue).not_to receive(:set_value)
      subject
    end
  end

  context 'dossier ready but administration field set', vcr: { cassette_name: 'daf_act_copy_amount_1' } do
    it 'amount to pay should be 0' do
      field = controle.dossier_field(dossier, controle.params[:champ_commande_gratuite])
      expect(field).to receive(:value).and_return('DOM')
      expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_montant_theorique], amount)
      expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_montant], 0)
      subject
    end
  end
end
