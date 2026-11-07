# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DossierLinkCheck do
  let(:controle) do
    described_class.new(champ: 'Inscription', demarches: [3335], message_mauvaise_demarche: 'Mauvaise démarche',
                        champs_identiques: { 'Numéro DN': 'Numéro DN', 'Numéro TAHITI': 'Numéro Tahiti' },
                        message_champs_differents: "ne correspond pas à l'inscription")
  end

  def dn(numero, naissance = '1980-01-01')
    double('Champ', label: 'Numéro DN', __typename: 'NumeroDnChamp', numero_dn: numero, date_de_naissance: naissance)
  end

  def inscription(*champs, numero: 3335)
    double('Dossier lié', demarche: double(number: numero), state: 'accepte', champs:)
  end

  def dossier(lie, *champs)
    lien = double('Lien', label: 'Inscription', __typename: 'DossierLinkChamp', string_value: '690745', dossier: lie)
    double('Dossier', number: 1, champs: [lien, *champs])
  end

  def messages_pour(dossier)
    controle.control(dossier)
    controle.messages.map(&:message)
  end

  it 'accepts the same DN, whatever the date of birth' do
    expect(messages_pour(dossier(inscription(dn('1234567', '1990-05-05')), dn('123 4567')))).to be_empty
  end

  it 'reports a different DN with the value of the linked dossier' do
    expect(messages_pour(dossier(inscription(dn('1234567')), dn('7654321'))))
      .to eq(["ne correspond pas à l'inscription (Numéro DN : 1234567)"])
  end

  it 'does not compare a field hidden on the dossier' do
    tahiti = double('Champ', label: 'Numéro Tahiti', __typename: 'SiretChamp', string_value: 'A12345')
    expect(messages_pour(dossier(inscription(dn('1234567'), tahiti), dn('1234567')))).to be_empty
  end

  it 'still reports a dossier of another procedure' do
    expect(messages_pour(dossier(inscription(numero: 1234), dn('1234567')))).to eq(['Mauvaise démarche'])
  end
end
