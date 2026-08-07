# frozen_string_literal: true

require 'rails_helper'

# Point d'entrée manuel : rejouer les contrôles sur un seul dossier
# (console ou `rake "dossiers:check[123456]"`), sans lancer le robot sur
# toute la démarche ni décaler son curseur de dernier passage.
RSpec.describe VerificationService do
  let(:service) { described_class.new }

  describe '.procedures_for' do
    before do
      allow(VerificationService).to receive(:configs).and_return(
        'a.yml' => {
          'entree_a' => { 'demarches' => [3602, 3915] },
          'template' => { 'champs' => [] }
        },
        'b.yml' => {
          'entree_b' => { 'demarches' => 3915 },
          'entree_c' => { 'demarches' => [1234] }
        }
      )
    end

    it 'retient toutes les entrées traitant la démarche, tous fichiers confondus' do
      expect(VerificationService.procedures_for(3915).map(&:first)).to eq(%w[entree_a entree_b])
    end

    it 'accepte une démarche déclarée en scalaire' do
      expect(VerificationService.procedures_for(1234).map(&:first)).to eq(['entree_c'])
    end

    it 'ne retourne rien pour une démarche non configurée' do
      expect(VerificationService.procedures_for(9999)).to be_empty
    end
  end

  describe '#check_one' do
    let(:md_dossier) { double('md_dossier', number: 123, demarche: double('demarche', number: 3602)) }
    let(:demarche) { double('Demarche', instructeurs: nil) }
    let(:controls) { [double('control', name: 'c1', :demarche= => nil)] }
    let(:relation) { double('Check::ActiveRecord_Relation', update_all: 1) }

    before do
      allow(DemarcheActions).to receive(:ping).and_return(true)
      allow(DemarcheActions).to receive(:get_demarche).and_return(demarche)
      allow(Check).to receive(:where).with(dossier: 123).and_return(relation)
      allow(VerificationService).to receive(:procedures_for).with(3602).and_return(
        [['ma_config', { 'demarches' => [3602], 'email_instructeur' => 'robot@ex.pf' }]]
      )
      allow(service).to receive(:on_dossier).and_yield(md_dossier)
      allow(service).to receive_messages(get_pieces_messages: {}, create_when_ok_tasks: nil, check_dossier: nil)
      allow(service).to receive(:create_controls) { service.instance_variable_set(:@controls, controls) }
    end

    it 'traite le dossier demandé' do
      service.check_one(123)

      expect(service).to have_received(:check_dossier).with(demarche, md_dossier, controls)
    end

    it 'périme les Checks du dossier pour imposer le retraitement' do
      service.check_one(123)

      expect(relation).to have_received(:update_all).with(version: 0)
    end

    it 'ne périme rien quand le forçage est désactivé' do
      service.check_one(123, force: false)

      expect(relation).not_to have_received(:update_all)
    end

    # Garde-fou : repositionner le curseur ferait sauter au robot tous les
    # dossiers modifiés depuis son dernier passage.
    it 'ne repositionne pas la date de dernier passage de la démarche' do
      expect(demarche).not_to receive(:checked_at=)
      expect(demarche).not_to receive(:save)

      service.check_one(123)
    end

    it 'échoue explicitement sur un dossier introuvable' do
      allow(service).to receive(:on_dossier).and_yield(nil)

      expect { service.check_one(123) }.to raise_error(ArgumentError, /introuvable/)
    end
  end
end
