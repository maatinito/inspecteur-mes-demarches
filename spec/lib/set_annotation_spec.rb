# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SetAnnotation do
  # Régression : sur une annotation destination typée (ex. IntegerNumberChamp),
  # le champ GraphQL `value` est aliasé en `intValue` (commit 0ad4ea8). Lire
  # l'annotation via `.value` lève « unfetched field `value' ». On doit passer
  # par une lecture typée (SetAnnotationValue.value_of).
  let(:task) { SetAnnotation.new(annotation: 'Montant accordé', valeur: '1000000') }
  let(:instructeur) { 'instructeur' }
  let(:demarche) { instance_double(Demarche, instructeur:) }
  let(:dossier) { double('dossier', state: 'en_construction') }

  let(:integer_annotation) do
    champ = double('IntegerNumberChamp', __typename: 'IntegerNumberChamp', int_value: nil)
    allow(champ).to receive(:value).and_raise("unfetched field `value'")
    champ
  end

  before do
    allow(task).to receive(:param_annotation).with(:annotation, warn_if_empty: false).and_return(integer_annotation)
    allow(SetAnnotationValue).to receive(:set_value).and_return(true)
    allow(task).to receive(:dossier_updated)
  end

  it 'lit une annotation IntegerNumber vide sans lever, et pose la valeur' do
    expect(SetAnnotationValue).to receive(:set_value).with(dossier, instructeur, 'Montant accordé', '1000000')
    expect { task.process(demarche, dossier) }.not_to raise_error
  end

  context "quand l'annotation IntegerNumber contient déjà une valeur" do
    let(:integer_annotation) do
      champ = double('IntegerNumberChamp', __typename: 'IntegerNumberChamp', int_value: 500_000)
      allow(champ).to receive(:value).and_raise("unfetched field `value'")
      champ
    end

    it "ne réécrit pas l'annotation" do
      expect(SetAnnotationValue).not_to receive(:set_value)
      task.process(demarche, dossier)
    end
  end
end
