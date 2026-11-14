# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Referentiel::Verrou do
  let(:dlnuf7) { 'mes-demarches: referentiel=DLNUF; proprietaire=7' }
  let(:dlnuf8) { 'mes-demarches: referentiel=DLNUF; proprietaire=8' }
  let(:archive) { 'mes-demarches: referentiel=archive' }
  let(:illisible) { 'mes-demarches: referentiel' }

  def mode!(description, lignes: -> { 0 })
    described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: description, lignes:)
  end

  def enregistrer(mode, proprietaire = nil)
    ReferentielTable.create!(backend: 'baserow', table_ref: '42', mode:, proprietaire:)
  end

  it 'ne compte pas les lignes quand le marqueur est archive' do
    lignes = -> { raise 'ne doit pas être appelé' }
    expect(described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: nil, lignes:)).to eq(:archive)
  end

  it 'adopte sans courriel une table DLNUF vide' do
    expect(Referentiel::Alerte).not_to receive(:informer)
    expect(described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: 'mes-demarches: referentiel=DLNUF; proprietaire=7', lignes: -> { 0 })).to eq(:dlnuf)
  end

  it 'adopte une table DLNUF déjà remplie et en informe une seule fois' do
    expect(Referentiel::Alerte).to receive(:informer).once.with(an_instance_of(ReferentielTable), /adoptée en DLNUF, 128 lignes/)
    2.times { described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: 'mes-demarches: referentiel=DLNUF; proprietaire=7', lignes: -> { 128 }) }
    expect(ReferentielTable.find_by(table_ref: '42')).to have_attributes(mode: 'dlnuf', proprietaire: 7)
  end

  it 'date le premier refus et le garde aux refus suivants' do
    ReferentielTable.create!(backend: 'baserow', table_ref: '42', mode: 'dlnuf', proprietaire: 7)
    2.times { expect { described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: nil, lignes: -> { 0 }) }.to raise_error(Referentiel::Verrou::Refus) }
    expect(ReferentielTable.last.refus_depuis).to be_within(5.seconds).of(Time.zone.now)
  end

  it 'efface la date de refus quand le marqueur est rétabli' do
    table = ReferentielTable.create!(backend: 'baserow', table_ref: '42', mode: 'dlnuf', proprietaire: 7, refus_depuis: 1.day.ago, alerte_le: 1.day.ago)
    described_class.mode!(backend: 'baserow', table_ref: '42', description_primaire: 'mes-demarches: referentiel=DLNUF; proprietaire=7', lignes: -> { 3 })
    expect(table.reload).to have_attributes(refus_depuis: nil, alerte_le: nil)
  end

  describe 'tableau des règles' do
    it 'marqueur illisible sans enregistrement : crée archive puis refuse' do
      expect { mode!(illisible) }.to raise_error(Referentiel::Verrou::Refus, /marqueur illisible/)
      expect(ReferentielTable.find_by(table_ref: '42')).to have_attributes(mode: 'archive')
    end

    it 'marqueur illisible avec enregistrement archive : refuse' do
      enregistrer('archive')
      expect { mode!(illisible) }.to raise_error(Referentiel::Verrou::Refus, /marqueur illisible/)
    end

    it 'marqueur illisible avec enregistrement dlnuf : refuse' do
      enregistrer('dlnuf', 7)
      expect { mode!(illisible) }.to raise_error(Referentiel::Verrou::Refus, /marqueur illisible/)
    end

    it 'absent + archive : crée archive' do
      expect(mode!(archive)).to eq(:archive)
      expect(ReferentielTable.find_by(table_ref: '42')).to have_attributes(mode: 'archive', proprietaire: nil)
    end

    it 'absent + DLNUF : crée dlnuf avec son propriétaire' do
      expect(mode!(dlnuf7)).to eq(:dlnuf)
      expect(ReferentielTable.find_by(table_ref: '42')).to have_attributes(mode: 'dlnuf', proprietaire: 7)
    end

    it 'archive + archive : archive' do
      enregistrer('archive')
      expect(mode!(archive)).to eq(:archive)
    end

    it 'dlnuf + DLNUF même propriétaire : dlnuf' do
      enregistrer('dlnuf', 7)
      expect(mode!(dlnuf7)).to eq(:dlnuf)
    end

    it 'dlnuf + DLNUF autre propriétaire : refuse' do
      enregistrer('dlnuf', 7)
      expect { mode!(dlnuf8) }.to raise_error(Referentiel::Verrou::Refus, /type ou propriétaire modifié/)
    end

    it 'dlnuf + archive : refuse' do
      enregistrer('dlnuf', 7)
      expect { mode!(archive) }.to raise_error(Referentiel::Verrou::Refus, /type ou propriétaire modifié/)
    end

    it 'archive + DLNUF : refuse' do
      enregistrer('archive')
      expect { mode!(dlnuf7) }.to raise_error(Referentiel::Verrou::Refus, /type ou propriétaire modifié/)
    end

    it 'le refus porte la table et nomme backend, table, types et date' do
      enregistrer('dlnuf', 7)
      expect { mode!(archive) }.to raise_error(Referentiel::Verrou::Refus) { |e|
        expect(e.table).to be_a(ReferentielTable)
        expect(e.message).to match(/baserow.*42.*dlnuf.*archive.*refus depuis/)
      }
    end
  end
end
