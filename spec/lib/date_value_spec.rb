# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DateValue do
  subject(:date) { described_class.iso8601('2026-07-27') }

  it 'reste construite dans sa propre classe' do
    expect(date).to be_a(described_class)
    expect(date).to be_a(Date)
  end

  it "s'affiche au format français" do
    expect(date.to_s).to eq('27/07/2026')
    expect("le #{date}").to eq('le 27/07/2026')
    expect([date].join(', ')).to eq('27/07/2026')
  end

  # Load-bearing : les mutations GraphQL sérialisent la valeur en JSON
  # (SetAnnotationValue.raw_set_value passe `value:` tel quel au client).
  # Un ISO8601Date est attendu côté serveur.
  it 'se sérialise en ISO en JSON' do
    expect(date.as_json).to eq('2026-07-27')
    expect({ value: date }.to_json).to eq('{"value":"2026-07-27"}')
  end

  # Load-bearing : Publipostage#generate_docx fait `[*v].join(', ')`.
  it 'ne se disperse pas au splat' do
    expect([*date].size).to eq(1)
  end

  # Load-bearing : SetAnnotationValue.typed_query dispatche sur la classe.
  it 'matche `when Date` dans un case' do
    branch = case date
             when String then 'String'
             when Date then 'Date'
             end
    expect(branch).to eq('Date')
  end

  it 'garde le comportement arithmétique et comparatif de Date' do
    expect(date).to eq(Date.new(2026, 7, 27))
    expect(date + 1).to eq(Date.new(2026, 7, 28))
    expect([Date.new(2026, 1, 1), date].max).to eq(date)
    expect(date).to be_present
  end

  describe '.from_iso' do
    # L'API type la valeur d'un DateChamp en ISO8601DateTime : une date peut donc
    # arriver comme minuit UTC. Il ne faut jamais la ramener au fuseau de
    # l'application (Pacific/Tahiti, UTC-10), sous peine de la faire reculer d'un
    # jour (minuit UTC = 26/07 14h00 à Tahiti, mais la date reste le 27).
    it 'ne convertit jamais de fuseau : une date à minuit UTC garde son jour' do
      value = described_class.from_iso('2026-07-27T00:00:00Z')
      expect(value.to_s).to eq('27/07/2026')
    end
  end
end

RSpec.describe DatetimeValue do
  subject(:datetime) { described_class.iso8601('2026-07-27T09:30:00+10:00') }

  it "s'affiche au format français avec l'heure" do
    expect(datetime.to_s).to eq('27/07/2026 à 09h30')
  end

  # Contre-exemple volontaire : hériter de Time donnerait `[*value].size == 10`
  # (Time#to_a) et casserait Publipostage#generate_docx.
  it 'hérite de DateTime et non de Time' do
    expect(datetime).to be_a(DateTime)
    expect([*datetime].size).to eq(1)
  end

  it 'se sérialise en ISO en JSON' do
    expect(datetime.as_json).to start_with('2026-07-27T09:30:00')
  end

  # Contrepartie de l'affichage avec l'heure : un template Sablon peut retomber
  # sur la date seule par «=mon_champ.date» (Sablon fait `public_send` sur la
  # valeur du contexte quand le champ de fusion contient un point).
  it 'expose la date seule, affichable au format français' do
    expect(datetime.date).to be_a(DateValue)
    expect(datetime.date.to_s).to eq('27/07/2026')
  end

  describe '.from_iso' do
    # Tahiti est à UTC-10 : heure locale = heure UTC - 10h. '2026-07-26T23:30:00Z'
    # (23h30 UTC le 26) donne donc 13h30 le 26 à Tahiti, pas le 27 à 09h30.
    it "ramène l'heure au fuseau de l'application (Pacific/Tahiti), quel que soit le décalage d'origine" do
      value = described_class.from_iso('2026-07-26T23:30:00Z')
      expect(value.to_s).to eq('26/07/2026 à 13h30')
    end

    it 'ne lève pas pour une valeur illisible (elle lève Date::Error, interceptée par FieldChecker)' do
      expect { described_class.from_iso('valeur-illisible') }.to raise_error(Date::Error)
    end
  end
end
