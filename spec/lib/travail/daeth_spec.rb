# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Travail::Daeth do
  include ActiveSupport::Testing::TimeHelpers

  let(:demarche) do
    demarche = double(Demarche)
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    demarche
  end
  let(:dossier) { Struct.new(:number, :state, :date_depot).new(438_520, 'en_instruction', date_depot) }

  let(:controle) { FactoryBot.build :daeth }
  let(:instructeur) { 'instructeur' }
  let(:amount) { 300 }

  subject do
    controle.process(demarche, dossier)
    controle
  end

  context 'params incorrect' do
    let(:controle) { FactoryBot.build :daeth, champs_par_travailleur: '1,2,3,4,5,6,7,8,9' }

    it 'should trigger error' do
      expect(controle.valid?).to be_falsey
      expect(controle.errors).to eq(["10 champs doivent être déclarés dans 'champs_par_travailleur'"])
    end
  end

  # Régression 0ad4ea8 : les `value` typés du fragment ChampInfo sont aliasés
  # (dateValue, checked, intValue…). L'ancienne lecture
  # `c.respond_to?(:value) ? c.value : c` rangeait l'objet GraphQL lui-même dans le
  # hash : `Date.parse` levait « no implicit conversion of DateChamp into String » et
  # la rente était toujours vue comme vraie.
  describe '#disabled_workers' do
    let(:date_depot) { Date.new(2025, 1, 1) }

    # Champ dont le `value` est aliasé côté GraphQL : comme en production, il ne
    # répond pas du tout à `value`.
    def aliased_champ(label, typename, accessors)
      double(label, { label:, __typename: typename }.merge(accessors))
    end

    def date_champ(label, iso) = aliased_champ(label, 'DateChamp', date_value: iso)
    def yes_no_champ(label, checked) = aliased_champ(label, 'YesNoChamp', checked:)
    def integer_champ(label, int) = aliased_champ(label, 'IntegerNumberChamp', int_value: int)
    def text_champ(label, value) = double(label, label:, __typename: 'TextChamp', value:)
    def list_champ(label, value) = double(label, label:, __typename: 'DropDownListChamp', value:)

    let(:cotorep_begin) { '2024-03-01' }
    let(:cotorep_end) { '2025-09-01' }
    let(:cotorep_row) do
      double('Row',
             champs: [
               list_champ('Situation', Travail::Daeth::STATUS_COTOREP),
               list_champ('Type de contrat', 'CDI'),
               date_champ('Date de début du contrat', '2024-07-01'),
               date_champ('Date de fin du contrat', nil),
               text_champ('Heures par semaine', '39'),
               list_champ('Catégorie de handicap', 'C'),
               date_champ('Date de début des droits COTOREP', cotorep_begin),
               date_champ('Date de fin des droits COTOREP', cotorep_end)
             ])
    end
    let(:pdd_row) do
      double('Row',
             champs: [
               list_champ('Situation', Travail::Daeth::STATUS_PDD),
               list_champ('Type de contrat', 'CDD'),
               date_champ('Date de début du contrat', '2024-01-15'),
               date_champ('Date de fin du contrat', '2024-12-31'),
               text_champ('Heures par semaine', ''),
               integer_champ("Taux d'IPP", 30),
               yes_no_champ('Rente', false)
             ])
    end

    before do
      allow(controle).to receive(:declaration_year).and_return(2024)
      allow(controle).to receive(:param_field).with(:champ_travailleurs, warn_if_empty: false)
                                              .and_return(double('RepetitionChamp', rows: [cotorep_row, pdd_row]))
    end

    it 'lit les dates comme des Date sans lever' do
      workers = nil
      expect { workers = controle.disabled_workers }.not_to raise_error
      expect(workers.first).to include(
        status: Travail::Daeth::STATUS_COTOREP,
        contract_type: 'CDI',
        contract_begin: Date.new(2024, 7, 1),
        contract_end: nil,
        contract_hours: 39,
        cotorep_category: 'C',
        cotorep_begin: Date.new(2024, 3, 1),
        cotorep_end: Date.new(2025, 9, 1)
      )
    end

    context 'dates COTOREP vides' do
      let(:cotorep_begin) { nil }
      let(:cotorep_end) { nil }

      it 'les remplace par les bornes de l’année de déclaration' do
        worker = controle.disabled_workers.first
        expect(worker[:cotorep_begin]).to eq(Date.new(2024, 1, 1))
        expect(worker[:cotorep_end]).to eq(Date.new(2025, 1, 1))
      end
    end

    it 'lit la rente comme un booléen et les heures vides comme nil' do
      expect(controle.disabled_workers.last).to include(
        status: Travail::Daeth::STATUS_PDD,
        contract_hours: nil,
        pdd_rate: 30,
        annuity: false
      )
    end
  end

  context 'params correct' do
    let(:date_depot) { Date.new(2025, 1, 1) }
    let(:fte) { 170.0 }
    let(:ecap_fte) { 1.0 }
    let(:default_duty) { 8 }
    let(:outsourcing) { 0 }
    let(:dismissed) { 0 }
    let(:surcharge) { 0 }
    let(:source_late_fee) { 0 }
    let(:computed_late_fee) { 0 }
    let(:disabled_worker_fte) { 0.0 }
    let(:disabled_worker_log) { '' }
    let(:levy) { 8_888_000 }
    let(:duty) { default_duty - disabled_worker_fte - outsourcing - dismissed }
    let(:disabled_workers) { [] }
    let(:default_numbers) do
      {
        Travail::Daeth::FTE => fte,
        Travail::Daeth::ECAP_FTE => ecap_fte,
        Travail::Daeth::ASSESSMENT_BASE => fte - ecap_fte,
        Travail::Daeth::DEFAULT_DUTY => default_duty,
        Travail::Daeth::DISMISSED_FTE => dismissed,
        Travail::Daeth::SURCHARGE => surcharge,
        Travail::Daeth::LATE_FEE => source_late_fee,
        Travail::Daeth::OUTSOURCING => outsourcing

      }
    end
    let(:numbers) do
      default_numbers.merge({
                              Travail::Daeth::DISABLED_WORKER_FTE => disabled_worker_fte,
                              Travail::Daeth::FINAL_DUTY => duty,
                              Travail::Daeth::TOTAL => levy + computed_late_fee + surcharge,
                              Travail::Daeth::DUE_AMOUNT => levy,
                              Travail::Daeth::LATE_FEE => computed_late_fee
                            })
    end

    before do
      expect(controle).to receive(:default_numbers).and_return(default_numbers)
      expect(controle).to receive(:disabled_workers).and_return(disabled_workers)
      expect(controle).to receive(:save_messages).with(disabled_worker_log)
      expect(controle).to receive(:save_results).with(numbers)
      travel_to Time.zone.local(2025, 4, 10, 12, 0, 0)
    end
    after { travel_back }

    context 'late_fee' do
      let(:disabled_workers) { [] }
      context 'not initialized and filing date after 31/03' do
        let(:date_depot) { Time.zone.local(2025, 4, 1, 0, 0, 0) }
        let(:computed_late_fee) { 222_200 }
        it 'triggers late_fee' do
          subject
        end
      end
      context 'not initialzed and filing date before 31/03' do
        it "doesn't trigger late_fee" do
          subject
        end
      end
      context 'initialzed and filing date after 31/03' do
        let(:date_depot) { Time.zone.local(2025, 4, 1, 0, 0, 0) }
        let(:source_late_fee) { 10 }
        let(:computed_late_fee) { 10 }
        it "doesn't trigger late_fee" do
          subject
        end
      end
    end

    context 'with small set of salaries' do
      let(:fte) { 15.0 }
      let(:ecap_fte) { 0 }
      let(:default_duty) { 0.0 }
      let(:levy) { 0.0 }

      let(:default_numbers) do
        {
          Travail::Daeth::FTE => fte,
          Travail::Daeth::ECAP_FTE => ecap_fte,
          Travail::Daeth::ASSESSMENT_BASE => fte - ecap_fte,
          Travail::Daeth::DEFAULT_DUTY => default_duty,
          Travail::Daeth::DISMISSED_FTE => dismissed,
          Travail::Daeth::SURCHARGE => surcharge,
          Travail::Daeth::LATE_FEE => source_late_fee,
          Travail::Daeth::OUTSOURCING => outsourcing

        }
      end
      it "doesn't trigger late_fee" do
        subject
      end
    end

    context 'with disabled_workers' do
      before do
        expect(controle).to receive(:declaration_year).at_least(:once).and_return(2024)
      end

      context 'with cotorep' do
        let(:disabled_workers) do
          [
            {
              status: Travail::Daeth::STATUS_COTOREP, # CDI Ok
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              cotorep_category: 'C',
              cotorep_begin: DateValue.new(2024, 1, 1),
              cotorep_end: DateValue.new(2025, 9, 1)
            },
            {
              status: Travail::Daeth::STATUS_COTOREP, # CDD ok
              contract_type: 'CDD',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              cotorep_category: 'C',
              cotorep_begin: DateValue.new(2024, 1, 1),
              cotorep_end: DateValue.new(2025, 9, 1)
            },
            {
              status: Travail::Daeth::STATUS_COTOREP, # CDI not present on 31/12
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 15),
              contract_hours: 39,
              cotorep_category: 'B',
              cotorep_begin: DateValue.new(2024, 1, 1),
              cotorep_end: DateValue.new(2025, 9, 1)
            },
            {
              status: Travail::Daeth::STATUS_COTOREP, # CDI after 1/10
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 10, 2),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              cotorep_category: 'B',
              cotorep_begin: DateValue.new(2024, 1, 1),
              cotorep_end: DateValue.new(2025, 9, 1)
            },
            {
              status: Travail::Daeth::STATUS_COTOREP, # CDI partial time < 50%
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 19,
              cotorep_category: 'B',
              cotorep_begin: DateValue.new(2024, 1, 1),
              cotorep_end: DateValue.new(2025, 9, 1)
            },
            {
              status: Travail::Daeth::STATUS_COTOREP, # CDI and cotorep validity dates out of scope
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              cotorep_category: 'C',
              cotorep_begin: DateValue.new(2023, 1, 1),
              cotorep_end: DateValue.new(2023, 12, 31)
            },
            {
              status: Travail::Daeth::STATUS_COTOREP, # CDI and cotorep validity dates Partially out of scope
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              cotorep_category: 'C',
              cotorep_begin: DateValue.new(2024, 8, 1),
              cotorep_end: DateValue.new(2024, 8, 31)
            },
            {
              status: Travail::Daeth::STATUS_COTOREP, # CDI and cotorep validity date start after contract_begin but before October 1fst
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              cotorep_category: 'C',
              cotorep_begin: DateValue.new(2024, 8, 1),
              cotorep_end: DateValue.new(2025, 8, 31)
            }

          ]
        end
        let(:disabled_worker_fte) { 5.205 }
        let(:disabled_worker_log) do
          <<~TEXT.chomp
            2 = Reconnu COTOREP: C, valide entre 01/01/2024 et 01/09/2025, h/sem: 100%  présence annuelle:100.0%
            2 = Reconnu COTOREP: C, valide entre 01/01/2024 et 01/09/2025, h/sem: 100%  présence annuelle:50.3%
            1 = Reconnu COTOREP: B, valide entre 01/01/2024 et 01/09/2025, h/sem: 100%  présence annuelle:45.9%
            1 = Reconnu COTOREP: B, valide entre 01/01/2024 et 01/09/2025, h/sem: 100%  présence annuelle:24.9%
            1 = Reconnu COTOREP: B, valide entre 01/01/2024 et 01/09/2025, h/sem: 48.7%  présence annuelle:100.0%
            2 = Reconnu COTOREP: C, valide entre 01/01/2023 et 31/12/2023, h/sem: 100%  présence annuelle:0.0%
            2 = Reconnu COTOREP: C, valide entre 01/08/2024 et 31/08/2024, h/sem: 100%  présence annuelle:8.5%
            2 = Reconnu COTOREP: C, valide entre 01/08/2024 et 31/08/2025, h/sem: 100%  présence annuelle:41.8%
          TEXT
        end
        let(:levy) { 3_105_245 }

        it 'should triggers levy' do
          subject
        end
      end

      context 'with working accident' do
        let(:disabled_workers) do
          [
            {
              status: Travail::Daeth::STATUS_PDD, # CDI Ok
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              pdd_rate: 30,
              annuity: true
            },
            {
              status: Travail::Daeth::STATUS_PDD, # CDD ok
              contract_type: 'CDD',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              pdd_rate: 30,
              annuity: true
            },
            {
              status: Travail::Daeth::STATUS_PDD, # CDI not present on 31/12
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 15),
              contract_hours: 39,
              pdd_rate: 30,
              annuity: true
            },
            {
              status: Travail::Daeth::STATUS_PDD, # CDI after 1/10
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 10, 2),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              pdd_rate: 30,
              annuity: true
            },
            {
              status: Travail::Daeth::STATUS_PDD, # CDI partial time < 50%
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 19,
              pdd_rate: 30,
              annuity: true
            },
            {
              status: Travail::Daeth::STATUS_PDD, # CDI but validity < 20%
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              pdd_rate: 19,
              annuity: true
            },
            {
              status: Travail::Daeth::STATUS_PDD, # CDI but no pension
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39,
              pdd_rate: 30,
              annuity: false
            }

          ]
        end
        let(:disabled_worker_fte) { 2.698 }
        let(:disabled_worker_log) do
          <<~TEXT.chomp
            1 = Victime d'accident du travail ou maladie professionnelle: avec pension, 30% d'invalidité, h/sem: 100%  présence annuelle:100.0%
            1 = Victime d'accident du travail ou maladie professionnelle: avec pension, 30% d'invalidité, h/sem: 100%  présence annuelle:50.3%
            1 = Victime d'accident du travail ou maladie professionnelle: avec pension, 30% d'invalidité, h/sem: 100%  présence annuelle:45.9%
            1 = Victime d'accident du travail ou maladie professionnelle: avec pension, 30% d'invalidité, h/sem: 100%  présence annuelle:24.9%
            1 = Victime d'accident du travail ou maladie professionnelle: avec pension, 30% d'invalidité, h/sem: 48.7%  présence annuelle:100.0%
            0 = Victime d'accident du travail ou maladie professionnelle: avec pension, 19% d'invalidité, h/sem: 100%  présence annuelle:100.0%
            0 = Victime d'accident du travail ou maladie professionnelle: sans pension, 30% d'invalidité, h/sem: 100%  présence annuelle:100.0%
          TEXT
        end
        let(:levy) { 5_890_522 }

        it 'should triggers levy' do
          subject
        end
      end

      context 'with disabled workers with pension' do
        let(:disabled_workers) do
          [
            {
              status: Travail::Daeth::STATUS_PENSION, # CDI Ok
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39
            },
            {
              status: Travail::Daeth::STATUS_PENSION, # CDD ok
              contract_type: 'CDD',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39
            },
            {
              status: Travail::Daeth::STATUS_PENSION, # CDI not present on 31/12
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 15),
              contract_hours: 39
            },
            {
              status: Travail::Daeth::STATUS_PENSION, # CDI after 1/10
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 10, 2),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 39
            },
            {
              status: Travail::Daeth::STATUS_PENSION, # CDI partial time < 50%
              contract_type: 'CDI',
              contract_begin: Date.new(2024, 7, 1),
              contract_end: Date.new(2024, 12, 31),
              contract_hours: 19
            }
          ]
        end
        let(:disabled_worker_fte) { 2.698 }
        let(:disabled_worker_log) do
          <<~TEXT.chomp
            1 = Pensionné invalide, h/sem: 100%  présence annuelle:100.0%
            1 = Pensionné invalide, h/sem: 100%  présence annuelle:50.3%
            1 = Pensionné invalide, h/sem: 100%  présence annuelle:45.9%
            1 = Pensionné invalide, h/sem: 100%  présence annuelle:24.9%
            1 = Pensionné invalide, h/sem: 48.7%  présence annuelle:100.0%
          TEXT
        end
        let(:levy) { 5_890_522 }

        it 'should triggers levy' do
          subject
        end
      end
    end
  end
end
