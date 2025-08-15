# frozen_string_literal: true

require 'rails_helper'
# require 'app/lib/inspector_task'

class TestFieldChecker < FieldChecker
  def check(_dossier)
    add_message('field', 'value', 'message') if @params[:fail]
  end

  def required_fields
    super + %i[fail]
  end
end

RSpec.describe FieldChecker do
  context 'controls' do
    let(:dossier) { FactoryBot.build(:dossier) }

    subject { TestFieldChecker.new({ fail: failed }) }

    before do
      subject.control(dossier)
    end

    context 'check succeed' do
      let(:failed) { false }

      it 'should have no message' do
        expect(subject.messages).to be_empty
      end
    end

    context 'check failed' do
      let(:failed) { true }

      it 'should have one message' do
        expect(subject.messages.size).to be 1
      end
    end
  end

  context 'instanciate', vcr: { cassette_name: 'field_checker_instanciate' } do
    let(:dossier_nb) { 296_392 }
    let(:dossier) { DossierActions.on_dossier(dossier_nb) }
    let(:source) { nil }
    let(:checker) { FieldChecker.new({}) }

    subject do
      checker.process(nil, dossier)
      checker.instanciate(template, source)
    end

    context 'fix template' do
      let(:template) { 'VALUE' }
      it 'generate the same' do
        expect(subject).to eq(template)
      end
    end

    context 'champ template' do
      let(:template) { 'à {Commune} / {Numéro Tahiti ITI}' }
      it 'inserts champ value' do
        expect(subject).to eq('à Arue - Tahiti - 98701 / C28723-001')
      end
    end

    context 'template with prefix/suffix on champ value' do
      let(:template) { '{(;Commune;)}' }
      it 'inserts champ value' do
        expect(subject).to eq('(Arue - Tahiti - 98701)')
      end
    end

    context 'template with prefix/suffix on empty value' do
      let(:template) { '--{(;Unknown;)}--' }
      it 'inserts champ value' do
        expect(subject).to eq('----')
      end
    end

    context 'template with source' do
      let(:template) { '--{(;Commune;)}--' }
      let(:source) { { Commune: 'Arue' } }
      it 'inserts champ value' do
        expect(subject).to eq('--(Arue)--')
      end
    end

    context 'ternary expressions' do
      let(:source) { { validated: true, status: false, name: 'John', empty: nil } }

      context 'simple ternary with boolean true' do
        let(:template) { '{validated?Approved:Rejected}' }
        it 'returns true value' do
          expect(subject).to eq('Approved')
        end
      end

      context 'simple ternary with boolean false' do
        let(:template) { '{status?Active:Inactive}' }
        it 'returns false value' do
          expect(subject).to eq('Inactive')
        end
      end

      context 'ternary with spaces' do
        let(:template) { '{validated ? Yes : No}' }
        it 'handles spaces correctly' do
          expect(subject).to eq('Yes')
        end
      end

      context 'ternary with quoted values' do
        let(:template) { '{validated ? "Avis favorable" : "Avis défavorable"}' }
        it 'removes quotes from values' do
          expect(subject).to eq('Avis favorable')
        end
      end

      context 'ternary with nil value' do
        let(:template) { '{empty?Present:Missing}' }
        it 'returns false value for nil' do
          expect(subject).to eq('Missing')
        end
      end

      context 'ternary with non-empty string' do
        let(:template) { '{name?HasName:NoName}' }
        it 'returns true value for present string' do
          expect(subject).to eq('HasName')
        end
      end

      context 'combined with regular template' do
        let(:template) { 'Status: {validated?Approved:Rejected} for {name}' }
        it 'processes both ternary and regular expressions' do
          expect(subject).to eq('Status: Approved for John')
        end
      end
    end
  end
end
