# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Schedule, type: :model do
  let(:quand) { { decalage_jours: 1, decalage_heures: 2 } }
  let(:params) do
    {
      champ_date_de_reference: 'champ', champ_stockage: 'stockage', taches: {}
    }.merge(quand)
  end

  subject { described_class.new(params) }

  before do
    allow(subject).to receive(:datetime_pivot).and_return(pivot)
  end

  shared_examples 'schedule run_at tests' do
    context 'when only decalage_jours and decalage_heures are present' do
      it 'returns the correct DateTime with applied day and hour offsets' do
        result = subject.send(:run_at)
        expected_time = Time.zone.parse('2024-10-13T02:00 -1000') + DateTime.parse(pivot).hour.hours # 1 jour et 2 heures ajoutés

        expect(result).to eq(expected_time)
      end
    end

    context 'when only heure is present' do
      let(:quand) { { heure: '14:30' } }

      it 'returns the DateTime with the fixed hour applied' do
        result = subject.send(:run_at)
        expected_time = Time.zone.parse('2024-10-12T14:30 -1000') # heure fixée à 14:30, pas de décalage

        expect(result).to eq(expected_time)
      end
    end

    context 'when no decalage_jours, decalage_heures, or heure are specified' do
      let(:quand) { {} }

      it 'returns the DateTime from datetime_pivot without modification' do
        result = subject.send(:run_at)
        expected_time = Time.zone.parse('2024-10-12T00:00 -1000') + DateTime.parse(pivot).hour.hours

        expect(result).to eq(expected_time)
      end
    end
  end

  describe '#schedule run_at with date returned by datetime_pivot' do
    let(:pivot) { '2024-10-12' }

    include_examples 'schedule run_at tests'
  end

  describe '#schedule run_at with datetime returned by datetime_pivot' do
    let(:pivot) { '2024-10-12T10:00' }

    include_examples 'schedule run_at tests'
  end

  describe '#task_identifier' do
    let(:pivot) { '2024-10-12' }

    context 'when identifiant parameter is present' do
      let(:params) do
        {
          champ_date_de_reference: 'champ',
          champ_stockage: 'stockage',
          taches: {},
          identifiant: 'rappel_3_mois'
        }
      end

      it 'returns schedule/{identifiant}' do
        expect(subject.send(:task_identifier)).to eq('schedule/rappel_3_mois')
      end
    end

    context 'when identifiant parameter is absent' do
      let(:params) do
        {
          champ_date_de_reference: 'champ',
          champ_stockage: 'stockage',
          taches: {}
        }
      end

      it 'returns the class itself for backward compatibility' do
        expect(subject.send(:task_identifier)).to eq(Schedule)
      end
    end

    context 'when identifiant parameter is blank' do
      let(:params) do
        {
          champ_date_de_reference: 'champ',
          champ_stockage: 'stockage',
          taches: {},
          identifiant: ''
        }
      end

      it 'returns the class itself for backward compatibility' do
        expect(subject.send(:task_identifier)).to eq(Schedule)
      end
    end
  end
end
