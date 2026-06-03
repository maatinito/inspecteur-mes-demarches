# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Style/OneClassPerFile, Naming/MethodParameterName

# Stub minimal d'un champ_descriptor GraphQL pour le Differ.
class TestDifferDescriptor
  attr_reader :id, :label, :__typename, :options, :other_option

  def initialize(id:, label:, typename:, options: nil, other_option: nil)
    @id = id
    @label = label
    @__typename = typename
    @options = options
    @other_option = other_option
  end
end

# Stub minimal d'un bloc répétable (avec champ_descriptors internes).
class TestDifferBlockDescriptor
  attr_reader :id, :label, :__typename, :champ_descriptors

  def initialize(id:, label:, champ_descriptors:)
    @id = id
    @label = label
    @__typename = 'RepetitionChampDescriptor'
    @champ_descriptors = champ_descriptors
  end
end

# Stub minimal d'un demarche_descriptor GraphQL.
# annotation_descriptors est optionnel — quand fourni, le Differ doit le
# concaténer aux champ_descriptors (comportement symétrique avec MainTableBuilder).
TestDifferDemarcheDescriptor = Struct.new(:champ_descriptors, :annotation_descriptors) do
  def initialize(champs, annotations = nil)
    super
  end
end

# rubocop:enable Style/OneClassPerFile, Naming/MethodParameterName

# rubocop:disable Metrics/BlockLength
RSpec.describe SchemaBuilders::Differ do
  let(:demarche) { create(:demarche) }
  let(:schema_target) do
    create(:schema_target,
           demarche: demarche,
           target_type: 'baserow',
           main_table_external_id: '101',
           excluded_field_ids: ['exclu_id'])
  end
  let(:adapter) { instance_double(SchemaBuilders::BaserowTarget) }

  let(:champ_a) { TestDifferDescriptor.new(id: 'a', label: 'Adresse', typename: 'TextChampDescriptor') }
  let(:champ_b) do
    TestDifferDescriptor.new(id: 'b', label: 'Statut', typename: 'DropDownListChampDescriptor', options: %w[Oui Non])
  end
  let(:champ_c) { TestDifferDescriptor.new(id: 'c', label: 'Email', typename: 'EmailChampDescriptor') }
  let(:champ_excluded) { TestDifferDescriptor.new(id: 'exclu_id', label: 'Notes', typename: 'TextChampDescriptor') }

  let(:demarche_descriptor) do
    TestDifferDemarcheDescriptor.new([champ_a, champ_b, champ_c, champ_excluded])
  end

  let(:differ) do
    described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: demarche_descriptor)
  end

  describe '#main_table_diff' do
    context 'avec une table cible existante' do
      before do
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Adresse', 'type' => 'text' },
                                                                              { 'name' => 'Statut', 'type' => 'text' }
                                                                            ])
      end

      it 'classe le champ conforme dans ok' do
        diff = differ.main_table_diff
        expect(diff[:ok].map { |f| f[:id] }).to include('a')
      end

      it 'classe le champ manquant dans to_add' do
        diff = differ.main_table_diff
        expect(diff[:to_add].map { |f| f[:id] }).to include('c')
      end

      it 'classe le champ avec type divergent dans to_modify (numeric vs text)' do
        numeric_champ = TestDifferDescriptor.new(id: 'n', label: 'Montant',
                                                 typename: 'IntegerNumberChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([numeric_champ])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Montant', 'type' => 'text' }
                                                                            ])
        diff = d.main_table_diff
        expect(diff[:to_modify].map { |f| f[:id] }).to include('n')
        expect(diff[:to_modify].first[:divergence]).to be_present
      end

      it 'classe les champs exclus dans excluded même s\'ils manquent côté cible' do
        diff = differ.main_table_diff
        expect(diff[:excluded].map { |f| f[:id] }).to eq(['exclu_id'])
        expect(diff[:to_add].map { |f| f[:id] }).not_to include('exclu_id')
      end

      it 'ignore les RepetitionChampDescriptor' do
        repetition = TestDifferBlockDescriptor.new(id: 'rep', label: 'Membres', champ_descriptors: [])
        descriptor = TestDifferDemarcheDescriptor.new([champ_a, repetition])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        diff = d.main_table_diff
        all_ids = diff.values.flatten.map { |f| f[:id] }
        expect(all_ids).not_to include('rep')
      end

      it 'ignore les HeaderSectionChampDescriptor (jamais dans aucune zone)' do
        header = TestDifferDescriptor.new(id: 'h1', label: 'Section', typename: 'HeaderSectionChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([champ_a, header])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        diff = d.main_table_diff
        all_ids = diff.values.flatten.map { |f| f[:id] }
        expect(all_ids).not_to include('h1')
      end

      it 'ignore les ExplicationChampDescriptor (jamais dans aucune zone)' do
        explication = TestDifferDescriptor.new(id: 'e1', label: 'Info', typename: 'ExplicationChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([champ_a, explication])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        diff = d.main_table_diff
        all_ids = diff.values.flatten.map { |f| f[:id] }
        expect(all_ids).not_to include('e1')
      end

      it 'ignore les types non supportés par le TypeMapper' do
        unsupported = TestDifferDescriptor.new(id: 'u1', label: 'Siret', typename: 'SiretChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([champ_a, unsupported])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        diff = d.main_table_diff
        all_ids = diff.values.flatten.map { |f| f[:id] }
        expect(all_ids).not_to include('u1')
      end

      it 'classe PhoneChampDescriptor vs phone_number côté Baserow comme ok' do
        phone = TestDifferDescriptor.new(id: 'p1', label: 'Téléphone', typename: 'PhoneChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([phone])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Téléphone',
                                                                                'type' => 'phone_number' }
                                                                            ])
        diff = d.main_table_diff
        expect(diff[:ok].map { |f| f[:id] }).to include('p1')
        expect(diff[:to_modify].map { |f| f[:id] }).not_to include('p1')
      end

      it 'classe TextChampDescriptor vs long_text côté Baserow comme to_modify' do
        text = TestDifferDescriptor.new(id: 't1', label: 'Notes courtes', typename: 'TextChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([text])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Notes courtes',
                                                                                'type' => 'long_text' }
                                                                            ])
        diff = d.main_table_diff
        expect(diff[:to_modify].map { |f| f[:id] }).to include('t1')
      end

      it 'crée un FormuleChampDescriptor en text quand le champ n\'existe pas côté cible' do
        formule = TestDifferDescriptor.new(id: 'f1', label: 'Total calculé', typename: 'FormuleChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([formule])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([])
        diff = d.main_table_diff
        added = diff[:to_add].find { |f| f[:id] == 'f1' }
        expect(added).to be_present
        expect(added[:type]).to eq('text')
      end

      it 'tolère n\'importe quel type cible pour un FormuleChampDescriptor déjà présent' do
        formule = TestDifferDescriptor.new(id: 'f1', label: 'Total calculé', typename: 'FormuleChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([formule])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        # L'utilisateur a manuellement converti la formule en type number côté Baserow
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Total calculé',
                                                                                'type' => 'number' }
                                                                            ])
        diff = d.main_table_diff
        expect(diff[:ok].map { |f| f[:id] }).to include('f1')
        expect(diff[:to_modify].map { |f| f[:id] }).not_to include('f1')
      end

      it 'tolère aussi le type formula côté cible pour un FormuleChampDescriptor' do
        formule = TestDifferDescriptor.new(id: 'f1', label: 'Total calculé', typename: 'FormuleChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([formule])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Total calculé',
                                                                                'type' => 'formula' }
                                                                            ])
        diff = d.main_table_diff
        expect(diff[:ok].map { |f| f[:id] }).to include('f1')
      end

      it 'dédupe les champs MD ayant le même label (garde le premier)' do
        first = TestDifferDescriptor.new(id: 'first', label: 'Superficie', typename: 'IntegerNumberChampDescriptor')
        second = TestDifferDescriptor.new(id: 'second', label: 'Superficie', typename: 'IntegerNumberChampDescriptor')
        descriptor = TestDifferDemarcheDescriptor.new([first, second])
        d = described_class.new(target: schema_target, adapter: adapter, demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([])
        allow(Rails.logger).to receive(:warn)

        diff = d.main_table_diff
        all_ids = diff.values.flatten.map { |f| f[:id] }
        expect(all_ids.count('first')).to eq(1)
        expect(all_ids).not_to include('second')
        expect(Rails.logger).to have_received(:warn).with(/doublon de label 'Superficie'/)
      end
    end

    context 'avec une table inexistante (premier Build)' do
      before do
        schema_target.update!(main_table_external_id: nil)
      end

      it 'classe tout en to_add (sauf exclus)' do
        diff = differ.main_table_diff
        expect(diff[:to_add].map { |f| f[:id] }).to contain_exactly('a', 'b', 'c')
        expect(diff[:excluded].map { |f| f[:id] }).to eq(['exclu_id'])
      end

      it 'ne fait pas d\'appel à adapter.get_table_fields' do
        expect(adapter).not_to receive(:get_table_fields)
        differ.main_table_diff
      end
    end

    context 'DropDownList avec otherOption=true' do
      it 'considère le type cible attendu comme text (pas single_select)' do
        dropdown = TestDifferDescriptor.new(
          id: 'dd1', label: 'Catégorie',
          typename: 'DropDownListChampDescriptor',
          options: %w[A B Autre],
          other_option: true
        )
        descriptor = TestDifferDemarcheDescriptor.new([dropdown])
        d = described_class.new(target: schema_target, adapter: adapter,
                                demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Catégorie',
                                                                                'type' => 'text' }
                                                                            ])

        diff = d.main_table_diff
        expect(diff[:ok].map { |f| f[:id] }).to include('dd1')
        expect(diff[:to_modify].map { |f| f[:id] }).not_to include('dd1')
      end

      it 'garde single_select pour otherOption=false (comportement par défaut)' do
        dropdown = TestDifferDescriptor.new(
          id: 'dd2', label: 'Civilité',
          typename: 'DropDownListChampDescriptor',
          options: %w[M Mme],
          other_option: false
        )
        descriptor = TestDifferDemarcheDescriptor.new([dropdown])
        d = described_class.new(target: schema_target, adapter: adapter,
                                demarche_descriptor: descriptor)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([
                                                                              { 'name' => 'Civilité',
                                                                                'type' => 'text' }
                                                                            ])

        diff = d.main_table_diff
        expect(diff[:to_modify].map { |f| f[:id] }).to include('dd2')
      end
    end

    context 'avec annotations privées' do
      it 'inclut les annotation_descriptors dans le diff main_table' do
        annotation = TestDifferDescriptor.new(id: 'ann1', label: 'Note interne',
                                              typename: 'TextChampDescriptor')
        descriptor_with_annotations = TestDifferDemarcheDescriptor.new(
          [champ_a], [annotation]
        )
        d = described_class.new(target: schema_target, adapter: adapter,
                                demarche_descriptor: descriptor_with_annotations)
        allow(adapter).to receive(:get_table_fields).with('101').and_return([])

        diff = d.main_table_diff
        all_ids = diff.values.flatten.map { |f| f[:id] }
        expect(all_ids).to include('ann1')
      end
    end
  end

  describe '#blocks_diff' do
    # Trois blocs : excluded (déjà dans excluded_block_descriptor_ids),
    # new (pas de SchemaBlockTarget encore), existing (avec backend_table_id).
    let(:block_excluded) do
      TestDifferBlockDescriptor.new(
        id: 'bloc_excluded', label: 'Activités annexes', champ_descriptors: []
      )
    end
    let(:block_new) do
      TestDifferBlockDescriptor.new(
        id: 'bloc_new', label: 'Pièces jointes',
        champ_descriptors: [
          TestDifferDescriptor.new(id: 'pj1', label: 'Document 1', typename: 'TextChampDescriptor')
        ]
      )
    end
    let(:block_existing) do
      TestDifferBlockDescriptor.new(
        id: 'bloc_existing', label: 'Membres',
        champ_descriptors: [
          TestDifferDescriptor.new(id: 'm_montant', label: 'Montant',
                                   typename: 'IntegerNumberChampDescriptor'),
          TestDifferDescriptor.new(id: 'm_nom', label: 'Nom', typename: 'TextChampDescriptor')
        ]
      )
    end

    let(:demarche_descriptor) do
      TestDifferDemarcheDescriptor.new([champ_a, block_excluded, block_new, block_existing])
    end

    before do
      schema_target.update!(excluded_block_descriptor_ids: ['bloc_excluded'])
      # SchemaBlockTarget existant pour bloc_existing
      create(:schema_block_target,
             schema_target: schema_target,
             block_descriptor_id: 'bloc_existing',
             backend_table_id: '500')
      allow(adapter).to receive(:get_table_fields).with('500').and_return([
                                                                            { 'name' => 'Nom', 'type' => 'text' },
                                                                            { 'name' => 'Montant', 'type' => 'text' }
                                                                          ])
      # Stub par défaut : aucune table détectée par nom. Les tests qui veulent
      # vérifier l'auto-détection re-stubbent avec une liste non vide.
      allow(adapter).to receive(:list_tables).and_return([])
    end

    it 'retourne le bloc exclus dans blocks_excluded' do
      diff = differ.blocks_diff
      expect(diff[:blocks_excluded]).to eq([{ id: 'bloc_excluded', label: 'Activités annexes' }])
    end

    it 'retourne les blocs inclus dans blocks (sans le bloc exclus)' do
      diff = differ.blocks_diff
      ids = diff[:blocks].map { |b| b[:id] }
      expect(ids).to contain_exactly('bloc_new', 'bloc_existing')
    end

    it 'auto-crée un SchemaBlockTarget pour un nouveau bloc' do
      expect { differ.blocks_diff }
        .to change { schema_target.schema_block_targets.where(block_descriptor_id: 'bloc_new').count }
        .from(0).to(1)
    end

    it 'crée le SchemaBlockTarget avec backend_table_id nil' do
      differ.blocks_diff
      new_bt = schema_target.schema_block_targets.find_by(block_descriptor_id: 'bloc_new')
      expect(new_bt.backend_table_id).to be_nil
    end

    it 'pour un bloc neuf (backend_table_id nil), tous les champs vont dans to_add' do
      diff = differ.blocks_diff
      entry = diff[:blocks].find { |b| b[:id] == 'bloc_new' }
      expect(entry[:diff][:to_add].map { |f| f[:id] }).to eq(['pj1'])
    end

    it 'pour un bloc existant, détecte le champ avec type divergent (to_modify)' do
      diff = differ.blocks_diff
      entry = diff[:blocks].find { |b| b[:id] == 'bloc_existing' }
      expect(entry[:diff][:to_modify].map { |f| f[:id] }).to include('m_montant')
      expect(entry[:diff][:ok].map { |f| f[:id] }).to include('m_nom')
    end

    it 'expose le schema_block_target dans chaque entrée bloc' do
      diff = differ.blocks_diff
      entry = diff[:blocks].find { |b| b[:id] == 'bloc_existing' }
      expect(entry[:schema_block_target]).to be_a(SchemaBlockTarget)
      expect(entry[:schema_block_target].block_descriptor_id).to eq('bloc_existing')
    end

    it 'est idempotent : un second appel ne crée pas de doublon' do
      differ.blocks_diff
      expect { differ.blocks_diff }
        .not_to(change { SchemaBlockTarget.count })
    end

    context 'DropDownList avec otherOption=true DANS un bloc' do
      it 'considère le champ dropdown libre interne au bloc comme text' do
        dropdown_in_block = TestDifferDescriptor.new(
          id: 'bdd1', label: 'Catégorie',
          typename: 'DropDownListChampDescriptor',
          options: %w[A B Autre],
          other_option: true
        )
        bloc = TestDifferBlockDescriptor.new(
          id: 'bloc_with_dropdown', label: 'Membres',
          champ_descriptors: [dropdown_in_block]
        )
        descriptor_with_bloc = TestDifferDemarcheDescriptor.new([bloc])
        schema_target.update!(excluded_block_descriptor_ids: [])
        create(:schema_block_target,
               schema_target: schema_target,
               block_descriptor_id: 'bloc_with_dropdown',
               backend_table_id: '600')
        allow(adapter).to receive(:get_table_fields).with('600').and_return([
                                                                              { 'name' => 'Catégorie',
                                                                                'type' => 'text' }
                                                                            ])

        d = described_class.new(target: schema_target, adapter: adapter,
                                demarche_descriptor: descriptor_with_bloc)
        diff = d.blocks_diff
        entry = diff[:blocks].find { |b| b[:id] == 'bloc_with_dropdown' }
        expect(entry[:diff][:ok].map { |f| f[:id] }).to include('bdd1')
        expect(entry[:diff][:to_modify].map { |f| f[:id] }).not_to include('bdd1')
      end
    end

    context 'avec annotations privées' do
      it 'inclut les blocs trouvés dans annotation_descriptors' do
        block_in_annotation = TestDifferBlockDescriptor.new(
          id: 'bloc_annot', label: 'Pièces contrôlées', champ_descriptors: []
        )
        descriptor_with_annotations = TestDifferDemarcheDescriptor.new(
          [champ_a], [block_in_annotation]
        )
        schema_target.update!(excluded_block_descriptor_ids: [])
        d = described_class.new(target: schema_target, adapter: adapter,
                                demarche_descriptor: descriptor_with_annotations)

        diff = d.blocks_diff
        ids = diff[:blocks].map { |b| b[:id] }
        expect(ids).to include('bloc_annot')
      end
    end

    context 'auto-détection de table existante par nom' do
      it 'persiste backend_table_id quand une table cible a le même nom que le bloc' do
        allow(adapter).to receive(:list_tables).with('17').and_return([
                                                                        { 'id' => 700, 'name' => 'Pièces jointes' },
                                                                        { 'id' => 701, 'name' => 'Autre' }
                                                                      ])
        allow(adapter).to receive(:get_table_fields).with('700').and_return([])

        differ.blocks_diff
        new_bt = schema_target.schema_block_targets.find_by(block_descriptor_id: 'bloc_new')
        expect(new_bt.backend_table_id).to eq('700')
      end

      it 'ne touche pas au backend_table_id si déjà persisté' do
        allow(adapter).to receive(:list_tables).with('17').and_return([
                                                                        { 'id' => 999, 'name' => 'Membres' }
                                                                      ])
        existing = schema_target.schema_block_targets.find_by(block_descriptor_id: 'bloc_existing')
        original = existing.backend_table_id
        differ.blocks_diff
        expect(existing.reload.backend_table_id).to eq(original)
      end

      it "n'appelle list_tables qu'une fois même avec plusieurs blocs neufs" do
        allow(adapter).to receive(:list_tables).with('17').and_return([])
        differ.blocks_diff
        expect(adapter).to have_received(:list_tables).with('17').once
      end
    end

    it 'respecte les exclusions de champ DANS un bloc' do
      block_existing_target = schema_target.schema_block_targets
                                           .find_by(block_descriptor_id: 'bloc_existing')
      block_existing_target.exclude_field!('m_nom')

      diff = differ.blocks_diff
      entry = diff[:blocks].find { |b| b[:id] == 'bloc_existing' }
      expect(entry[:diff][:excluded].map { |f| f[:id] }).to include('m_nom')
      expect(entry[:diff][:ok].map { |f| f[:id] }).not_to include('m_nom')
    end
  end
end
# rubocop:enable Metrics/BlockLength
