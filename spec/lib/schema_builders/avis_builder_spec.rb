# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe SchemaBuilders::AvisBuilder do
  describe 'avec une cible Baserow' do
    let(:target) { instance_double(SchemaBuilders::BaserowTarget) }
    let(:builder) { described_class.new(target: target) }

    before do
      allow(target).to receive(:table_ref) { |_app, table_id| table_id }
      allow(target).to receive(:show_dossier_number)
    end

    describe '#preview' do
      it 'retourne le schéma fixe avec le link_row Dossier' do
        preview = builder.preview(application_id: 17, main_table_id: 100)

        expect(preview[:table_name]).to eq('Avis')
        expect(preview[:application_id]).to eq(17)
        expect(preview[:main_table_id]).to eq(100)

        names = preview[:fields].map { |f| f[:name] }
        expect(names).to include(
          'Dossier', 'Question', 'Réponse', 'Libellé question',
          'Réponse fermée', 'Date question', 'Date réponse',
          'Email expert', 'Email demandeur', 'Pièces jointes'
        )
      end

      it 'le champ Dossier est un link_row pointant vers la table principale' do
        preview = builder.preview(application_id: 17, main_table_id: 100)
        dossier = preview[:fields].find { |f| f[:name] == 'Dossier' }

        expect(dossier).to include(
          type: 'link_row',
          link_row_table_id: 100,
          has_related_field: true,
          link_row_multiple_relationships: false
        )
      end
    end

    describe '#build!' do
      it 'appelle target.create_table quand la table Avis n\'existe pas' do
        allow(target).to receive(:table_exists?).with(17, 'Avis').and_return(false)
        allow(target).to receive(:create_table).with(17, 'Avis', kind_of(Array)).and_return({ 'id' => 200 })

        result = builder.build!(application_id: 17, main_table_id: 100)

        expect(target).to have_received(:create_table)
        expect(result[:table_id]).to eq(200)
        expect(result[:action]).to eq(:created)
        expect(result[:table_name]).to eq('Avis')
      end

      it 'appelle target.update_fields quand la table existe déjà' do
        allow(target).to receive(:table_exists?).with(17, 'Avis').and_return(true)
        allow(target).to receive(:list_tables).with(17).and_return([{ 'id' => 200, 'name' => 'Avis' }])
        allow(target).to receive(:update_fields)

        result = builder.build!(application_id: 17, main_table_id: 100)

        expect(target).to have_received(:update_fields).with(200, kind_of(Array))
        expect(result[:table_id]).to eq(200)
        expect(result[:action]).to eq(:updated)
      end

      it 'transmet le link_row Dossier dans les champs créés' do
        captured = nil
        allow(target).to receive(:table_exists?).and_return(false)
        allow(target).to receive(:create_table) do |_app, _name, fields|
          captured = fields
          { 'id' => 1 }
        end

        builder.build!(application_id: 17, main_table_id: 100)

        dossier = captured.find { |f| f[:name] == 'Dossier' }
        expect(dossier).to include(type: 'link_row', link_row_table_id: 100)
      end
    end
  end

  describe 'avec une cible Grist' do
    let(:target) { instance_double(SchemaBuilders::GristTarget) }
    let(:builder) { described_class.new(target: target, type_mapper: SchemaBuilders::TypeMapper.for(:grist)) }

    def field(fields, col_id) = fields.find { |f| f[:id] == col_id }

    it 'décrit les colonnes au format Grist, Dossier en référence vers la table principale' do
      fields = builder.preview(application_id: 'doc1', main_table_id: 'Dossiers')[:fields]

      expect(fields.map { |f| f[:fields][:label] }).to include(
        'Avis', 'Dossier', 'Question', 'Réponse', 'Libellé question', 'Réponse fermée',
        'Date question', 'Date réponse', 'Email expert', 'Email demandeur', 'Pièces jointes'
      )
      expect(field(fields, 'Avis')[:fields][:type]).to eq('Text')
      expect(field(fields, 'Dossier')[:fields][:type]).to eq('Ref:Dossiers')
      expect(fields.find { |f| f[:fields][:label] == 'Pièces jointes' }[:fields][:type]).to eq('Attachments')
    end

    # Avec l'heure : le délai de réponse d'un avis se compte souvent en jours, parfois en heures.
    it 'garde l’heure des dates de question et de réponse' do
      fields = builder.preview(application_id: 'doc1', main_table_id: 'Dossiers')[:fields]

      dates = fields.select { |f| f[:fields][:label].start_with?('Date') }.map { |f| f[:fields][:type] }
      expect(dates).to all(start_with('DateTime'))
    end

    # Un document Grist peut réunir plusieurs démarches (DIREN : 3135 et 3091) :
    # une table « Avis » unique n'aurait qu'une table principale possible.
    it 'nomme la table Avis_<n° démarche>' do
      expect(builder.preview(application_id: 'doc1', main_table_id: 'Dossiers', demarche_number: 3135)[:table_name])
        .to eq('Avis_3135')
    end

    it 'crée la table et fait afficher le numéro de dossier dans la colonne Dossier' do
      allow(target).to receive(:table_exists?).with('doc1', 'Avis_3135').and_return(false)
      allow(target).to receive(:create_table).and_return({ 'id' => 'Avis_3135' })
      allow(target).to receive(:show_dossier_number)

      result = builder.build!(application_id: 'doc1', main_table_id: 'Dossiers', demarche_number: 3135)

      expect(target).to have_received(:create_table).with('doc1', 'Avis_3135', kind_of(Array))
      expect(target).to have_received(:show_dossier_number).with('doc1', 'Avis_3135', 'Dossiers')
      expect(result).to include(table_id: 'Avis_3135', action: :created, table_name: 'Avis_3135')
    end

    it 'met à jour une table existante via sa référence composite' do
      allow(target).to receive(:table_exists?).and_return(true)
      allow(target).to receive(:list_tables).with('doc1').and_return([{ 'id' => 'Avis_3135' }])
      allow(target).to receive(:table_ref).with('doc1', 'Avis_3135').and_return('doc1:Avis_3135')
      allow(target).to receive(:update_fields)
      allow(target).to receive(:show_dossier_number)

      result = builder.build!(application_id: 'doc1', main_table_id: 'Dossiers', demarche_number: 3135)

      expect(target).to have_received(:update_fields).with('doc1:Avis_3135', kind_of(Array))
      expect(result).to include(table_id: 'Avis_3135', action: :updated)
    end
  end
end
# rubocop:enable Metrics/BlockLength
