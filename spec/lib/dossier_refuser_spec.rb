# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DossierRefuser do
  let(:demarche) { instance_double(Demarche, instructeur: 'robot') }
  let(:motif) { double('Motif', label: "Motif de l'abattage", __typename: 'TextChamp', value: 'Newcastle confirmée', string_value: 'Newcastle confirmée') }
  let(:dossier) { double('Dossier', id: 'RG9z', number: 700_001, state: 'en_instruction', champs: [], annotations: [motif]) }
  let(:resultat) { double('Resultat', errors: double(present?: false)) }

  before { allow(MesDemarches).to receive(:query).and_return(resultat) }

  it 'instancie les champs du dossier dans la motivation' do
    described_class.new(motivation: "Abattage du lot — motif : {Motif de l'abattage}").process(demarche, dossier)
    expect(MesDemarches).to have_received(:query)
      .with(anything, variables: hash_including(motivation: 'Abattage du lot — motif : Newcastle confirmée'))
  end

  it 'laisse intacte une motivation sans variable' do
    described_class.new(motivation: 'Refus simple.').process(demarche, dossier)
    expect(MesDemarches).to have_received(:query).with(anything, variables: hash_including(motivation: 'Refus simple.'))
  end
end
