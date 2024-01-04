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
  end
end
