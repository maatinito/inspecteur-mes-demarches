# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilders::ReferentielDlnuf do
  let(:colonnes) do
    [{ 'id' => 1, 'name' => 'Dossier', 'type' => 'number', 'primary' => true, 'description' => nil },
     { 'id' => 9115, 'name' => 'Email usager', 'type' => 'email', 'primary' => false }]
  end
  let(:client) { instance_double(Baserow::StructureClient, get_table_fields: colonnes) }

  it 'pose le marqueur sur une table neuve, sans rien enregistrer en base' do
    expect(client).to receive(:update_field).with(1, description: a_string_ending_with('mes-demarches: referentiel=DLNUF; proprietaire=9115'))
    expect(described_class.new(client:).finaliser!(861, creee: true)).to eq(9115)
    expect(ReferentielTable.count).to eq(0)
  end

  it 'ne réécrit rien quand le marqueur concorde' do
    colonnes.first['description'] = 'mes-demarches: referentiel=DLNUF; proprietaire=9115'
    expect(client).not_to receive(:update_field)
    described_class.new(client:).finaliser!(861, creee: false)
  end

  it 'refuse de marquer une table existante' do
    expect(client).not_to receive(:update_field)
    expect { described_class.new(client:).finaliser!(861, creee: false) }.to raise_error(Referentiel::Verrou::Refus)
  end

  it 'refuse un propriétaire discordant sans le réécrire' do
    colonnes.first['description'] = 'mes-demarches: referentiel=DLNUF; proprietaire=1'
    expect(client).not_to receive(:update_field)
    expect { described_class.new(client:).finaliser!(861, creee: true) }.to raise_error(Referentiel::Verrou::Refus)
  end

  it 'refuse sans colonne Email usager' do
    colonnes.pop
    expect { described_class.new(client:).finaliser!(861, creee: true) }.to raise_error(Referentiel::Verrou::Refus)
  end

  it 'lit le type déclaré par la table' do
    expect(described_class.new(client:).type_lu(861)).to eq(:archive)
    colonnes.first['description'] = 'mes-demarches: referentiel=DLNUF; proprietaire=9115'
    expect(described_class.new(client:).type_lu(861)).to eq(:dlnuf)
    colonnes.first['description'] = 'mes demarches: referentiel=DLNUF'
    expect(described_class.new(client:).type_lu(861)).to eq(:invalid)
  end

  it 'rétablir exige un enregistrement sur ce robot' do
    expect { described_class.new(client:).retablir!(861) }.to raise_error(Referentiel::Verrou::Refus)
  end

  it 'rétablit le marqueur du type enregistré' do
    ReferentielTable.create!(backend: 'baserow', table_ref: '861', mode: 'archive')
    colonnes.first['description'] = "Numéro\nmes-demarches: referentiel=DLNUF; proprietaire=9115"
    expect(client).to receive(:update_field).with(1, description: 'Numéro')
    described_class.new(client:).retablir!(861)
  end

  it 'refuse de rétablir le marqueur d\'une table dont le type est encore inconnu' do
    ReferentielTable.create!(backend: 'baserow', table_ref: '861', mode: 'inconnu')
    expect(client).not_to receive(:update_field)
    expect { described_class.new(client:).retablir!(861) }
      .to raise_error(Referentiel::Verrou::Refus, /type de cette table n'est pas encore connu de ce robot.*à la main/)
  end

  it 'liste les colonnes fichier' do
    colonnes << { 'id' => 3, 'name' => 'RIB', 'type' => 'file' }
    expect(described_class.new(client:).colonnes_fichier(861)).to eq(['RIB'])
  end

  describe '#tables_liees' do
    let(:tables) { [{ 'id' => 861, 'name' => 'Dossiers' }, { 'id' => 862, 'name' => 'Membres' }, { 'id' => 863, 'name' => 'Membres archive' }, { 'id' => 864, 'name' => 'Sans lien' }] }
    let(:lien) { ->(cible) { [{ 'name' => 'Dossier', 'type' => 'link_row', 'link_row_table_id' => cible }] } }

    before do
      allow(client).to receive(:list_tables).with(17).and_return(tables)
      allow(client).to receive(:get_table_fields).with(862).and_return(lien.call(861))
      allow(client).to receive(:get_table_fields).with(863).and_return(lien.call(555))
      allow(client).to receive(:get_table_fields).with(864).and_return([{ 'name' => 'Dossier', 'type' => 'number' }])
    end

    it 'ne rend que les tables dont la colonne Dossier pointe vers la table principale' do
      expect(described_class.new(client:).tables_liees(17, 861)).to eq([862])
    end
  end

  describe '#application_de' do
    it 'lit l\'application de la table sur Baserow' do
      allow(client).to receive(:get_table).with(861).and_return({ 'id' => 861, 'database_id' => 17 })
      expect(described_class.new(client:).application_de(861)).to eq(17)
    end
  end
end
