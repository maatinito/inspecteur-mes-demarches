# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SchemaBuilders::AvisBuilder do
  describe 'avec une cible Baserow' do
    let(:target) { instance_double(SchemaBuilders::BaserowTarget) }
    let(:builder) { described_class.new(target: target) }

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
    let(:target) { SchemaBuilders::GristTarget.new(client: instance_double(Grist::Client)) }

    it 'lève NotImplementedError à l\'initialisation' do
      expect { described_class.new(target: target) }
        .to raise_error(NotImplementedError, /Avis non supporté/)
    end
  end
end
