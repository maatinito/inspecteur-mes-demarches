# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Daf::Instruction do
  # Régression : `DATE DE CERTIFICATION` est un DateChamp dont le champ GraphQL
  # `value` est aliasé en `dateValue` (commit 0ad4ea8). L'appeler directement
  # levait « unfetched field `value' ». On doit passer par champ_value (→ date_value).
  let(:controle) do
    Daf::Instruction.new(paiement1: [], paiement2: [], sans_paiement1: [], sans_paiement2: [])
  end
  let(:instructeur) { 'instructeur' }
  let(:demarche) { instance_double(Demarche, instructeur:) }
  let(:dossier) { double('dossier', date_depot: '2026-06-19') }

  let(:date_champ) do
    champ = double('DateChamp', __typename: 'DateChamp', date_value: nil)
    allow(champ).to receive(:value).and_raise("unfetched field `value'")
    champ
  end

  before do
    controle.instance_variable_set(:@dossier, dossier)
    allow(controle).to receive(:annotation).with('DATE DE CERTIFICATION').and_return(date_champ)
    allow(SetAnnotationValue).to receive(:set_value)
  end

  it 'lit une annotation DateChamp vide sans lever, et pose la date de dépôt' do
    expect(SetAnnotationValue).to receive(:set_value)
      .with(dossier, instructeur, 'DATE DE CERTIFICATION', DateTime.iso8601('2026-06-19'))
    expect { controle.set_certification_date(demarche, dossier) }.not_to raise_error
  end
end
