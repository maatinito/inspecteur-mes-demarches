# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MesDemarchesToGrist::AvisSyncer do
  let(:columns) do
    {
      'Avis' => { id: 'Avis', label: 'Avis', type: 'Text', isFormula: false, formula: '' },
      'Dossier' => { id: 'Dossier', label: 'Dossier', type: 'Ref:Dossiers', isFormula: false, formula: '' },
      'Question' => { id: 'Question', label: 'Question', type: 'Text', isFormula: false, formula: '' },
      'Reponse' => { id: 'Reponse', label: 'Réponse', type: 'Text', isFormula: false, formula: '' },
      'Date_question' => { id: 'Date_question', label: 'Date question', type: 'DateTime:UTC', isFormula: false, formula: '' },
      'Date_reponse' => { id: 'Date_reponse', label: 'Date réponse', type: 'DateTime:UTC', isFormula: false, formula: '' },
      'Email_expert' => { id: 'Email_expert', label: 'Email expert', type: 'Text', isFormula: false, formula: '' },
      'Delai' => { id: 'Delai', label: 'Délai', type: 'Numeric', isFormula: true, formula: '$Date_reponse - $Date_question' },
      'Pieces_jointes' => { id: 'Pieces_jointes', label: 'Pièces jointes', type: 'Attachments', isFormula: false, formula: '' }
    }
  end
  let(:client) { instance_double(Grist::Client) }
  let(:table) { instance_double(Grist::Table, columns: columns, client: client) }
  let(:uploader) { instance_double(Grist::FileUploader) }

  def avis(avis_id:, reponse: 'Favorable', question_answer: nil, attachments: [])
    double('Avis', id: avis_id, question: 'Votre avis ?', reponse: reponse, question_label: nil,
                   question_answer: question_answer, date_question: '2026-05-01T10:00:00Z',
                   date_reponse: '2026-05-03T16:00:00Z', expert: double(email: 'expert@diren.pf'),
                   claimant: double(email: 'agent@diren.pf'), attachments: attachments)
  end

  subject(:syncer) { described_class.new(doc_id: 'doc', table_id: 'Avis_3135', main_table_id: 'Dossiers', options: {}) }

  before do
    allow(Grist::Config).to receive(:table).with('doc', 'Avis_3135', nil).and_return(table)
    allow(Grist::Config).to receive(:client).and_return(client)
    allow(Grist::FileUploader).to receive(:new).and_return(uploader)
    allow(table).to receive(:find_by).with('Dossier', 7).and_return([])
    allow(table).to receive(:upsert_records)
    allow(table).to receive(:delete_records)
  end

  it 'upserte chaque avis par son id, rattaché à la ligne du dossier' do
    allow(MesDemarches::AvisFetcher).to receive(:fetch).with(616_223).and_return([avis(avis_id: 'A1')])

    syncer.sync(616_223, 7)

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:require]).to eq('Avis' => 'A1')
      expect(records.first[:fields]).to include('Dossier' => 7, 'Question' => 'Votre avis ?', 'Reponse' => 'Favorable',
                                                'Date_question' => Time.utc(2026, 5, 1, 10).to_i,
                                                'Date_reponse' => Time.utc(2026, 5, 3, 16).to_i,
                                                'Email_expert' => 'expert@diren.pf')
    end
  end

  it "n'écrit ni dans une colonne formule ni dans une colonne inconnue" do
    allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis(avis_id: 'A1')])

    syncer.sync(616_223, 7)

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:fields].keys).not_to include('Delai', 'Email demandeur', 'Email_demandeur')
    end
  end

  # dateReponse = date de dernière modification de l'avis : sans réponse, la
  # recopier donnerait un délai nul.
  it 'vide Date réponse pour un avis en attente' do
    allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis(avis_id: 'A1', reponse: nil)])

    syncer.sync(616_223, 7)

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:fields]).to include('Date_reponse' => nil)
    end
  end

  it 'réutilise une pièce jointe déjà présente et télécharge les nouvelles' do
    deja = double(filename: 'plan.pdf', byte_size: 10, url: 'https://md/plan.pdf')
    nouvelle = double(filename: 'avis.pdf', byte_size: 20, url: 'https://md/avis.pdf')
    allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis(avis_id: 'A1', attachments: [deja, nouvelle])])
    allow(table).to receive(:find_by).with('Dossier', 7)
                                     .and_return([{ 'id' => 3, 'fields' => { 'Avis' => 'A1', 'Pieces_jointes' => ['L', 41] } }])
    allow(client).to receive(:get_attachment_metadata).with('doc', 41).and_return('fileName' => 'plan.pdf', 'fileSize' => 10)
    allow(uploader).to receive(:download_and_upload).with('https://md/avis.pdf', 'avis.pdf').and_return(42)

    syncer.sync(616_223, 7)

    expect(table).to have_received(:upsert_records) do |records|
      expect(records.first[:fields]['Pieces_jointes']).to eq(['L', 41, 42])
    end
  end

  it 'supprime les avis disparus du dossier' do
    allow(MesDemarches::AvisFetcher).to receive(:fetch).and_return([avis(avis_id: 'A1')])
    allow(table).to receive(:find_by).with('Dossier', 7).and_return([{ 'id' => 3, 'fields' => { 'Avis' => 'A1' } },
                                                                     { 'id' => 4, 'fields' => { 'Avis' => 'A0' } }])

    syncer.sync(616_223, 7)

    expect(table).to have_received(:delete_records).with([4])
  end

  # Un document peut réunir plusieurs démarches : la table n'est synchronisée
  # que si sa colonne Dossier pointe vers la table principale de la démarche.
  it 'ignore une table Avis rattachée à une autre table principale' do
    columns['Dossier'][:type] = 'Ref:Dossiers_demarche_3091'
    allow(MesDemarches::AvisFetcher).to receive(:fetch)
    allow(Rails.logger).to receive(:warn)

    syncer.sync(616_223, 7)

    expect(MesDemarches::AvisFetcher).not_to have_received(:fetch)
    expect(Rails.logger).to have_received(:warn).with(/Avis_3135.*Dossiers_demarche_3091/)
  end
end
