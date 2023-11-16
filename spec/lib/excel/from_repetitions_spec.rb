# frozen_string_literal: true

require 'rspec'

describe 'Excel::FromRepetitions' do
  let(:dossier_nb) { 376_077 }
  let(:dossier) { DossierActions.on_dossier(dossier_nb) }
  let(:demarche) { double(Demarche) }
  let(:instructeur) { 'instructeur' }

  before do
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    allow(SendMessage).to receive(:send)
    allow(controle).to receive(:instructeur_id_for).and_return(1)
  end

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'valid control' do
    let(:controle) { FactoryBot.build :excel_from_repetitions }
    let(:generated) { 'generated.xlsx' }
    let(:data_filename) { 'storage/from_repetition.yml' }
    let(:columns) { ['Nom fourni', 'Type', 'Complément'].to_h { |v| [v, Regexp.new(Regexp.quote(v), 'i')] } }

    before do
      expect(SetAnnotationValue).to receive(:set_piece_justificative_on_annotation)
      allow(Tempfile).to receive(:create).and_yield(File.open(generated, 'w+'))
      allow_any_instance_of(Excel::FromRepetitions).to receive(:data_filename).and_return(data_filename)
      FileUtils.rm_f(data_filename)
    end
    after { FileUtils.rm_f(generated) }

    context 'with perfect variables' do
      let(:result) do
        [
          { 'Nom fourni' => 'Hetre petrus', 'Type' => 'Brut', 'Complément' => 'Bois usagé' },
          { 'Nom fourni' => 'Pin', 'Type' => 'Contreplaqué, bois de placage, bois reconstitué', 'Complément' => 'Bois neuf' },
          { 'Nom fourni' => 'Pin', 'Type' => 'Brut', 'Complément' => 'Bois neuf' }
        ]
      end
      it 'generate xlsx', vcr: 'from_repetition-1' do
        subject
        xlsx = Roo::Spreadsheet.open(generated)
        rows = xlsx.sheet(0).parse(columns)
        expect(rows).to match(result)
        expect(File).to exist(data_filename)
      end
      it 'generate xlsx', vcr: 'from_repetition-1' do
        subject
        FileUtils.rm_f(generated)
        expect(controle).not_to receive(:send_document)
        controle.process(demarche, dossier) # 2nd time
      end
    end
  end
end
