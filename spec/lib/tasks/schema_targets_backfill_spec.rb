# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'schema_targets:backfill', type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('schema_targets:backfill')
  end

  let(:task) { Rake::Task['schema_targets:backfill'] }
  let(:baserow_adapter) { instance_double(SchemaBuilders::BaserowTarget) }
  let(:grist_adapter)   { instance_double(SchemaBuilders::GristTarget) }

  before do
    allow(SchemaBuilders::BaserowTarget).to receive(:new).and_return(baserow_adapter)
    allow(SchemaBuilders::GristTarget).to receive(:new).and_return(grist_adapter)
    # Defaults: aucun workspace côté Baserow ni Grist (les tests les surchargent).
    allow(baserow_adapter).to receive(:list_workspaces).and_return([])
    allow(grist_adapter).to receive(:list_workspaces).and_return([])
  end

  after { task.reenable }

  it 'crée une SchemaTarget pour une démarche déjà synchronisée dans Baserow' do
    demarche = create(:demarche)

    allow(baserow_adapter).to receive(:list_workspaces).and_return([{ 'id' => 42, 'name' => 'WS' }])
    allow(baserow_adapter).to receive(:list_applications).with(42).and_return([{ 'id' => 17, 'name' => 'App' }])
    allow(baserow_adapter).to receive(:list_tables).with(17).and_return([
                                                                          { 'id' => 99, 'name' => "Dossiers démarche #{demarche.id}" }
                                                                        ])

    expect { task.invoke }.to change(SchemaTarget, :count).by(1)

    target = SchemaTarget.find_by(demarche: demarche, target_type: 'baserow')
    expect(target).not_to be_nil
    expect(target.workspace_external_id).to eq('42')
    expect(target.application_external_id).to eq('17')
    expect(target.main_table_external_id).to eq('99')
    expect(target.avis_table_external_id).to be_nil
  end

  it 'capture également la table Avis si présente dans la même application' do
    demarche = create(:demarche)

    allow(baserow_adapter).to receive(:list_workspaces).and_return([{ 'id' => 42 }])
    allow(baserow_adapter).to receive(:list_applications).with(42).and_return([{ 'id' => 17 }])
    allow(baserow_adapter).to receive(:list_tables).with(17).and_return([
                                                                          { 'id' => 99, 'name' => "Dossiers démarche #{demarche.id}" },
                                                                          { 'id' => 200, 'name' => 'Avis' }
                                                                        ])

    task.invoke

    target = SchemaTarget.find_by(demarche: demarche, target_type: 'baserow')
    expect(target.main_table_external_id).to eq('99')
    expect(target.avis_table_external_id).to eq('200')
  end

  it 'est idempotent (rejouer ne duplique pas)' do
    demarche = create(:demarche)
    create(:schema_target, demarche: demarche, target_type: 'baserow')

    expect { task.invoke }.not_to change(SchemaTarget, :count)
  end

  it 'ignore les démarches sans table correspondante' do
    create(:demarche)

    allow(baserow_adapter).to receive(:list_workspaces).and_return([{ 'id' => 42 }])
    allow(baserow_adapter).to receive(:list_applications).with(42).and_return([{ 'id' => 17 }])
    allow(baserow_adapter).to receive(:list_tables).with(17).and_return([
                                                                          { 'id' => 99, 'name' => 'Une autre table' }
                                                                        ])

    expect { task.invoke }.not_to change(SchemaTarget, :count)
  end

  it 'gère les erreurs API sans crasher' do
    create(:demarche)

    allow(baserow_adapter).to receive(:list_workspaces).and_raise(StandardError, 'Baserow down')
    allow(grist_adapter).to receive(:list_workspaces).and_raise(StandardError, 'Grist down')

    expect { task.invoke }.not_to raise_error
    expect(SchemaTarget.count).to eq(0)
  end

  it 'détecte une démarche déjà synchronisée dans Grist (id de table sans accents)' do
    demarche = create(:demarche)

    allow(grist_adapter).to receive(:list_workspaces).and_return([{ 'id' => 10 }])
    allow(grist_adapter).to receive(:list_applications).with(10).and_return([{ 'id' => 'doc1' }])
    allow(grist_adapter).to receive(:list_tables).with('doc1').and_return([
                                                                            { 'id' => "Dossiers démarche #{demarche.id}" }
                                                                          ])

    expect { task.invoke }.to change(SchemaTarget, :count).by(1)
    target = SchemaTarget.find_by(demarche: demarche, target_type: 'grist')
    expect(target).not_to be_nil
    expect(target.application_external_id).to eq('doc1')
    expect(target.main_table_external_id).to eq("Dossiers démarche #{demarche.id}")
  end
end
