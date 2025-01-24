# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Travail::Daeth do
  let(:dossier_nb) { 383_486 }
  let(:dossier) { DossierActions.on_dossier(dossier_nb) }
  let(:demarche) do
    demarche = double(Demarche)
    allow(demarche).to receive(:instructeur).and_return(instructeur)
    demarche
  end
  let(:dossier) { OpenStruct.new(number: 438_520, state: 'en_instruction') }

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

  context 'params correct' do
    let(:fte) { 170.0 }
    let(:ecap_fte) { 1.0 }
    let(:default_duty) { 8 }
    let(:outsourcing) { 0 }
    let(:dismissed) { 0 }
    let(:surcharge) { 0 }
    let(:late_fee) { 0 }
    let(:disabled_worker_fte) { 0 }
    let(:disabled_worker_log) { '' }
    let(:duty) { default_duty - disabled_worker_fte - outsourcing - dismissed }
    let(:default_numbers) do
      {
        Travail::Daeth::FTE => fte,
        Travail::Daeth::ECAP_FTE => ecap_fte,
        Travail::Daeth::ASSESSMENT_BASE => fte - ecap_fte,
        Travail::Daeth::DEFAULT_DUTY => default_duty,
        Travail::Daeth::DISMISSED_FTE => dismissed,
        Travail::Daeth::SURCHARGE => surcharge,
        Travail::Daeth::LATE_FEE => late_fee,
        Travail::Daeth::OUTSOURCING => outsourcing

      }
    end
    let(:numbers) do
      default_numbers.merge({
                              Travail::Daeth::DISABLED_WORKER_FTE => disabled_worker_fte,
                              Travail::Daeth::FINAL_DUTY => duty,
                              Travail::Daeth::TOTAL => levy + late_fee + surcharge,
                              Travail::Daeth::DUE_AMOUNT => levy
                            })
    end

    before do
      expect(controle).to receive(:declaration_year).at_least(:once).and_return(2024)
      expect(controle).to receive(:default_numbers).and_return(default_numbers)
      expect(controle).to receive(:disabled_workers).and_return(disabled_workers)
      expect(controle).to receive(:save_messages).with(disabled_worker_log)
      expect(controle).to receive(:save_results).with(numbers)
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
            cotorep_begin: Date.new(2024, 1, 1),
            cotorep_end: Date.new(2025, 9, 1)
          },
          {
            status: Travail::Daeth::STATUS_COTOREP, # CDD ok
            contract_type: 'CDD',
            contract_begin: Date.new(2024, 7, 1),
            contract_end: Date.new(2024, 12, 31),
            contract_hours: 39,
            cotorep_category: 'C',
            cotorep_begin: Date.new(2024, 1, 1),
            cotorep_end: Date.new(2025, 9, 1)
          },
          {
            status: Travail::Daeth::STATUS_COTOREP, # CDI not present on 31/12
            contract_type: 'CDI',
            contract_begin: Date.new(2024, 7, 1),
            contract_end: Date.new(2024, 12, 15),
            contract_hours: 39,
            cotorep_category: 'B',
            cotorep_begin: Date.new(2024, 1, 1),
            cotorep_end: Date.new(2025, 9, 1)
          },
          {
            status: Travail::Daeth::STATUS_COTOREP, # CDI after 1/10
            contract_type: 'CDI',
            contract_begin: Date.new(2024, 10, 2),
            contract_end: Date.new(2024, 12, 31),
            contract_hours: 39,
            cotorep_category: 'B',
            cotorep_begin: Date.new(2024, 1, 1),
            cotorep_end: Date.new(2025, 9, 1)
          },
          {
            status: Travail::Daeth::STATUS_COTOREP, # CDI partial time < 50%
            contract_type: 'CDI',
            contract_begin: Date.new(2024, 7, 1),
            contract_end: Date.new(2024, 12, 31),
            contract_hours: 19,
            cotorep_category: 'B',
            cotorep_begin: Date.new(2024, 1, 1),
            cotorep_end: Date.new(2025, 9, 1)
          },
          {
            status: Travail::Daeth::STATUS_COTOREP, # CDI and cotorep validity dates out of scope
            contract_type: 'CDI',
            contract_begin: Date.new(2024, 7, 1),
            contract_end: Date.new(2024, 12, 31),
            contract_hours: 39,
            cotorep_category: 'C',
            cotorep_begin: Date.new(2023, 1, 1),
            cotorep_end: Date.new(2023, 12, 31)
          },
          {
            status: Travail::Daeth::STATUS_COTOREP, # CDI and cotorep validity dates Partially out of scope
            contract_type: 'CDI',
            contract_begin: Date.new(2024, 7, 1),
            contract_end: Date.new(2024, 12, 31),
            contract_hours: 39,
            cotorep_category: 'C',
            cotorep_begin: Date.new(2024, 8, 1),
            cotorep_end: Date.new(2024, 8, 31)
          },
          {
            status: Travail::Daeth::STATUS_COTOREP, # CDI and cotorep validity date start after contract_begin but before October 1fst
            contract_type: 'CDI',
            contract_begin: Date.new(2024, 7, 1),
            contract_end: Date.new(2024, 12, 31),
            contract_hours: 39,
            cotorep_category: 'C',
            cotorep_begin: Date.new(2024, 8, 1),
            cotorep_end: Date.new(2025, 8, 31)
          }

        ]
      end
      let(:disabled_worker_fte) { 5.200 }
      let(:disabled_worker_log) do
        <<~TEXT.chomp
          2 = Reconnu COTOREP: C, valide entre 2024-01-01 et 2025-09-01, h/sem: 100%  présence annuelle:100.0%
          2 = Reconnu COTOREP: C, valide entre 2024-01-01 et 2025-09-01, h/sem: 100%  présence annuelle:50.3%
          1 = Reconnu COTOREP: B, valide entre 2024-01-01 et 2025-09-01, h/sem: 100%  présence annuelle:45.9%
          1 = Reconnu COTOREP: B, valide entre 2024-01-01 et 2025-09-01, h/sem: 100%  présence annuelle:24.9%
          1 = Reconnu COTOREP: B, valide entre 2024-01-01 et 2025-09-01, h/sem: 48.7%  présence annuelle:100.0%
          2 = Reconnu COTOREP: C, valide entre 2023-01-01 et 2023-12-31, h/sem: 100%  présence annuelle:0.0%
          2 = Reconnu COTOREP: C, valide entre 2024-08-01 et 2024-08-31, h/sem: 100%  présence annuelle:8.2%
          2 = Reconnu COTOREP: C, valide entre 2024-08-01 et 2025-08-31, h/sem: 100%  présence annuelle:41.8%
        TEXT
      end
      let(:levy) { 2_869_272 }

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
      let(:levy) { 5_433_171 }

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
      let(:levy) { 5_433_171 }

      it 'should triggers levy' do
        subject
      end
    end
  end

  # context 'dossier ready', vcr: { cassette_name: 'daeth_1' } do
  #   let(:repetition) { dossier.annotations.find { |champ| champ.__typename == 'RepetitionChamp' } }
  #   let(:page_field) { repetition.champs.find { |champ| champ.__typename == 'IntegerNumberChamp' } }
  #
  #   it 'amount should be set' do
  #     expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_montant_theorique], amount)
  #     expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, controle.params[:champ_montant], amount)
  #     subject
  #   end
  # end
end
