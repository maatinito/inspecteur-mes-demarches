# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AvisToBlocRepetable do
  let(:demarche) { double('demarche', instructeur: 'instructeur_123') }
  let(:dossier) { double('dossier', id: 'dossier_456', state: 'en_instruction') }

  let(:expert_profile) { double('expert', id: 'expert_1', email: 'expert@gov.pf') }
  let(:claimant_profile) { double('claimant', id: 'claimant_1', email: 'claimant@gov.pf') }

  let(:avis) do
    double('avis',
           id: 'avis_1',
           question: 'Que pensez-vous de ce dossier ?',
           reponse: 'Le dossier est conforme aux exigences.',
           question_label: 'Êtes-vous favorable ?',
           question_answer: true,
           date_question: '2024-01-15T10:00:00Z',
           date_reponse: '2024-01-16T14:30:00Z',
           expert: expert_profile,
           claimant: claimant_profile)
  end

  let(:params) do
    {
      bloc_destination: 'Avis consolidés',
      attributs: {
        'Expert' => '{expert.email}',
        'Question' => '{question}',
        'Réponse' => '{reponse}',
        'Avis' => '{question_answer?Favorable:Défavorable}',
        'Service' => '{organisation}'
      }
    }
  end

  subject { described_class.new(params) }

  before do
    # Mock de la requête GraphQL pour récupérer les avis
    allow(dossier).to receive(:number).and_return(123_456)

    graphql_result = double('graphql_result',
                            errors: [],
                            data: double('data',
                                         dossier: double('dossier', avis: [avis])))

    allow(MesDemarches).to receive(:query)
      .with(AvisToBlocRepetable::Query::DossierAvis, variables: { dossier: 123_456 })
      .and_return(graphql_result)

    allow(subject).to receive(:instructeur_id).and_return('instructeur_123')
    allow(subject).to receive(:dossier_updated)
    allow(subject).to receive(:must_check?).and_return(true)
  end

  describe '#process' do
    context 'without baserow integration' do
      before do
        allow(SetAnnotationValue).to receive(:allocate_blocks).and_return(
          double('repetition', rows: [
                   double('row', champs: [
                            double('champ', label: 'Expert', id: 'champ_1'),
                            double('champ', label: 'Question', id: 'champ_2'),
                            double('champ', label: 'Réponse', id: 'champ_3'),
                            double('champ', label: 'Avis', id: 'champ_4'),
                            double('champ', label: 'Service', id: 'champ_5')
                          ])
                 ])
        )

        allow(SetAnnotationValue).to receive(:value_of).and_return(nil)
        allow(SetAnnotationValue).to receive(:raw_set_value)
      end

      it 'processes avis and creates repetition block' do
        expect(SetAnnotationValue).to receive(:allocate_blocks)
          .with(dossier, 'instructeur_123', 'Avis consolidés', 1)

        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with('dossier_456', 'instructeur_123', 'champ_1', 'expert@gov.pf')

        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with('dossier_456', 'instructeur_123', 'champ_2', 'Que pensez-vous de ce dossier ?')

        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with('dossier_456', 'instructeur_123', 'champ_3', 'Le dossier est conforme aux exigences.')

        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with('dossier_456', 'instructeur_123', 'champ_4', 'Favorable')

        # Le champ Service sera vide car pas de données Baserow
        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with('dossier_456', 'instructeur_123', 'champ_5', '')

        subject.process(demarche, dossier)
      end
    end

    context 'with baserow integration' do
      let(:baserow_table) { double('baserow_table') }
      let(:baserow_params) do
        params.merge(
          baserow: {
            'table_id' => 12_345,
            'match_column' => 'email',
            'config_name' => 'tftn'
          }
        )
      end

      subject { described_class.new(baserow_params) }

      before do
        allow(Baserow::Config).to receive(:table).and_return(baserow_table)
        allow(baserow_table).to receive(:search_normalized).and_return([
                                                                         { 'email' => 'expert@gov.pf', 'organisation' => 'Direction de la Santé', 'fonction' => 'Médecin chef' }
                                                                       ])

        allow(SetAnnotationValue).to receive(:allocate_blocks).and_return(
          double('repetition', rows: [
                   double('row', champs: [
                            double('champ', label: 'Expert', id: 'champ_1'),
                            double('champ', label: 'Service', id: 'champ_5')
                          ])
                 ])
        )

        allow(SetAnnotationValue).to receive(:value_of).and_return('')
        allow(SetAnnotationValue).to receive(:raw_set_value)
      end

      it 'enriches data with baserow information' do
        expect(Baserow::Config).to receive(:table)
          .with(12_345, 'tftn', 'Experts')

        expect(baserow_table).to receive(:search_normalized)
          .with('email', 'expert@gov.pf')

        expect(SetAnnotationValue).to receive(:raw_set_value)
          .with('dossier_456', 'instructeur_123', 'champ_5', 'Direction de la Santé')

        subject.process(demarche, dossier)
      end

      it 'memoizes baserow table instance' do
        # Premier appel - doit créer l'instance
        expect(Baserow::Config).to receive(:table)
          .with(12_345, 'tftn', 'Experts')
          .once
          .and_return(baserow_table)

        # Premier accès
        table1 = subject.send(:baserow_table)
        # Deuxième accès - doit utiliser l'instance mémorisée
        table2 = subject.send(:baserow_table)

        expect(table1).to eq(table2)
        expect(table1).to eq(baserow_table)
      end
    end

    context 'with filters' do
      let(:filtered_params) do
        params.merge(
          filtres: {
            expert_emails: ['expert@gov.pf'],
            avec_reponse: true
          }
        )
      end

      subject { described_class.new(filtered_params) }

      it 'applies filters correctly' do
        expect(subject.send(:should_include_avis?, avis)).to be true
      end

      context 'when avis does not match filters' do
        let(:filtered_params) do
          params.merge(
            filtres: {
              expert_emails: ['other@gov.pf']
            }
          )
        end

        it 'excludes avis that do not match' do
          expect(subject.send(:should_include_avis?, avis)).to be false
        end
      end
    end

    context 'when GraphQL query fails' do
      before do
        error_result = double('error_result',
                              errors: [double('error', message: 'GraphQL Error')],
                              data: nil)

        allow(MesDemarches).to receive(:query)
          .with(AvisToBlocRepetable::Query::DossierAvis, variables: { dossier: 123_456 })
          .and_return(error_result)

        allow(Rails.logger).to receive(:error)
      end

      it 'logs error and returns empty array' do
        expect(Rails.logger).to receive(:error)
          .with('Erreur lors de la récupération des avis pour le dossier 123456: GraphQL Error')

        result = subject.send(:fetch_avis, dossier)
        expect(result).to eq([])
      end
    end
  end

  describe '#flatten_avis' do
    it 'flattens avis structure with dot notation' do
      result = subject.send(:flatten_avis, avis)

      expect(result).to include(
        'id' => 'avis_1',
        'question' => 'Que pensez-vous de ce dossier ?',
        'reponse' => 'Le dossier est conforme aux exigences.',
        'question_label' => 'Êtes-vous favorable ?',
        'question_answer' => true,
        'date_question' => '2024-01-15T10:00:00Z',
        'date_reponse' => '2024-01-16T14:30:00Z',
        'expert.id' => 'expert_1',
        'expert.email' => 'expert@gov.pf',
        'claimant.id' => 'claimant_1',
        'claimant.email' => 'claimant@gov.pf'
      )
    end

    context 'with baserow data' do
      let(:baserow_table) { double('baserow_table') }
      let(:baserow_params) do
        {
          bloc_destination: 'Test',
          attributs: { 'Test' => '{test}' },
          baserow: {
            'table_id' => 12_345,
            'match_column' => 'email'
          }
        }
      end

      subject { described_class.new(baserow_params) }

      before do
        allow(baserow_table).to receive(:search_normalized).and_return([
                                                                         { 'organisation' => 'Direction de la Santé', 'fonction' => 'Médecin chef' }
                                                                       ])
      end

      it 'merges baserow data into the hash' do
        result = subject.send(:flatten_avis, avis, baserow_table)

        expect(result).to include(
          'expert.email' => 'expert@gov.pf',
          'organisation' => 'Direction de la Santé',
          'fonction' => 'Médecin chef'
        )
      end
    end
  end

  describe 'ternary expressions integration' do
    let(:ternary_params) do
      {
        bloc_destination: 'Test',
        attributs: {
          'Statut' => '{questionAnswer?Approuvé:Rejeté}',
          'Expert Info' => '{expert.email ? expert.email : "Non renseigné"}'
        }
      }
    end

    subject { described_class.new(ternary_params) }

    it 'processes ternary expressions correctly' do
      flattened = subject.send(:flatten_avis, avis)

      # Test ternary with boolean (snake_case)
      result1 = subject.instanciate('{question_answer?Approuvé:Rejeté}', flattened)
      expect(result1).to eq('Approuvé')

      # Test ternary with string presence - la clé expert.email existe dans le hash aplati
      result2 = subject.instanciate('{expert.email ? "Expert présent" : "Non renseigné"}', flattened)
      expect(result2).to eq('Expert présent')
    end
  end
end
