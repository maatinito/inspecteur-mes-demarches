# frozen_string_literal: true

require 'rails_helper'

# Caractérisation des sorties produites pour un champ date. Ces attentes portent
# sur des chaînes visibles par les usagers (messages, champs de fusion .docx) :
# elles doivent rester vraies quelle que soit la représentation interne choisie.
RSpec.describe FieldChecker do
  let(:checker) { FieldChecker.new({}) }

  # Un DateChamp réel ne répond pas à `value` : le fragment ChampInfo l'aliase en
  # `dateValue` (commit 0ad4ea8).
  def date_champ(label, iso)
    double(label, label:, __typename: 'DateChamp', date_value: iso)
  end

  let(:champ) { date_champ('Date du jugement', '2026-07-27') }
  let(:dossier) { double('Dossier', number: 123, champs: [champ]) }

  before { checker.instance_variable_set(:@dossier, dossier) }

  it 'interpole la date au format français dans un message' do
    expect(checker.instanciate('Jugement du {Date du jugement}.'))
      .to eq('Jugement du 27/07/2026.')
  end

  it 'produit une valeur affichable au format français' do
    expect(checker.champ_value(champ).to_s).to eq('27/07/2026')
    expect(checker.champs_to_values([champ]).join(', ')).to eq('27/07/2026')
  end

  # Publipostage#generate_docx : `[*v].join(', ')` sur chaque valeur du contexte.
  it 'reste un scalaire une fois splatté comme dans generate_docx' do
    value = checker.champ_value(champ)
    expect([*value].join(', ')).to eq('27/07/2026')
  end

  # ConditionalField#process_condition normalise avec `value&.to_s` avant de
  # chercher la clé dans `valeurs:`.
  it 'se normalise en clé de condition identique' do
    expect(checker.champs_to_values([champ]).first.to_s).to eq('27/07/2026')
  end

  it 'rend une chaîne vide pour un champ date non renseigné' do
    expect(checker.champ_value(date_champ('Date du jugement', nil))).to eq('')
  end

  it 'ne retient pas un champ date vide dans les valeurs' do
    expect(checker.champs_to_values([date_champ('Date du jugement', nil)])).to eq([])
  end

  describe 'valeur exploitable par les plugins' do
    it 'rend un objet date comparable et calculable' do
      value = checker.champ_value(champ)
      expect(value).to be_a(Date)
      expect(value).to eq(Date.new(2026, 7, 27))
      expect(value.year).to eq(2026)
    end

    # Changement de sortie assumé : aujourd'hui l'heure est perdue (même branche
    # que DateChamp, format %d/%m/%Y). Voir « Décision » en tête de plan.
    it 'rend un DatetimeValue affichant l’heure pour un champ date-heure' do
      datetime_champ = double('DatetimeChamp', label: 'Horodatage', __typename: 'DatetimeChamp',
                                               string_value: '2026-07-27T09:30:00+10:00')
      value = checker.champ_value(datetime_champ)
      expect(value).to be_a(DatetimeValue)
      expect(value.to_s).to eq('27/07/2026 à 09h30')
      expect(value.date.to_s).to eq('27/07/2026')
    end
  end
end
