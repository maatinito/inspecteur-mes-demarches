# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ConfigurationsBaserow do
  describe '.demarches_synchronisees_vers' do
    let(:synchro) { ->(table_id) { { 'baserow_sync' => { 'baserow' => { 'table_id' => table_id, 'token_config' => 'x' } } } } }

    before do
      allow(VerificationService).to receive(:configs).and_return(
        'a.yml' => {
          'modele' => synchro.call(101),
          'liste' => %w[en_construction en_instruction],
          'directe' => { 'demarches' => [10, 11], 'when_ok' => [synchro.call(101)] },
          'imbriquee' => {
            'demarches' => [12],
            'when_ok' => [{ 'conditional_field' => { 'champ' => 'Type', 'valeurs' => { 'Oui' => [synchro.call('101')] } } }]
          },
          'autre_table' => { 'demarches' => [13], 'when_ok' => [synchro.call(102)] }
        },
        'b.yml' => {
          'controle' => { 'demarches' => 14, 'controles' => [synchro.call(101)] },
          'sans_synchro' => { 'demarches' => [15], 'when_ok' => [{ 'baserow_sync' => 'invalide' }] }
        }
      )
    end

    it 'rend les démarches des entrées qui synchronisent vers la table, à toute profondeur' do
      expect(described_class.demarches_synchronisees_vers('101')).to eq([10, 11, 12, 14])
    end

    it 'compare les identifiants de table comme des chaînes' do
      expect(described_class.demarches_synchronisees_vers(102)).to eq([13])
    end

    it 'rend une liste vide quand aucune entrée ne vise la table' do
      expect(described_class.demarches_synchronisees_vers(999)).to eq([])
    end
  end
end
