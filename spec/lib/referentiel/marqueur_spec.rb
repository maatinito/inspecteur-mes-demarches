# frozen_string_literal: true

require 'rails_helper'

describe Referentiel::Marqueur do
  describe '.parse' do
    it { expect(described_class.parse(nil)).to be_nil }
    it { expect(described_class.parse('Numéro du dossier')).to be_nil }
    it { expect(described_class.parse("x\n  MES-DEMARCHES:  Referentiel = DLNUF ;proprietaire=12 ; inconnue=1")).to eq('referentiel' => 'DLNUF', 'proprietaire' => '12', 'inconnue' => '1') }
    it('deux lignes') { expect(described_class.parse("mes-demarches: a=1\nmes-demarches: b=2")).to eq(:invalid) }
    it('faute de préfixe') { expect(described_class.parse('mes démarches : referentiel=DLNUF')).to eq(:invalid) }
    it('clé répétée') { expect(described_class.parse('mes-demarches: a=1; a=2')).to eq(:invalid) }
    it('sans paire') { expect(described_class.parse('mes-demarches:')).to eq(:invalid) }
    it('sans =') { expect(described_class.parse('mes-demarches: DLNUF')).to eq(:invalid) }
    it('contrat inconnu') { expect(described_class.parse('mes-demarches: referentiel=DLNUF; contrat=2')).to eq(:invalid) }
  end

  describe '.type_table' do
    it { expect(described_class.type_table(nil)).to eq([:archive, nil]) }
    it { expect(described_class.type_table('mes-demarches: referentiel=archive')).to eq([:archive, nil]) }
    it { expect(described_class.type_table('mes-demarches: contrat=1')).to eq([:archive, nil]) }
    it { expect(described_class.type_table('mes-demarches: referentiel=dlnuf; proprietaire=9115')).to eq([:dlnuf, 9115]) }
    it('DLNUF sans propriétaire') { expect(described_class.type_table('mes-demarches: referentiel=DLNUF')).to eq(:invalid) }
    it('propriétaire non numérique') { expect(described_class.type_table('mes-demarches: referentiel=DLNUF; proprietaire=Email')).to eq(:invalid) }
    it('type inconnu') { expect(described_class.type_table('mes-demarches: referentiel=autre')).to eq(:invalid) }
    it('clé présente mais vide') { expect(described_class.type_table('mes-demarches: referentiel=')).to eq(:invalid) }
  end

  describe '.reference_pj?' do
    it { expect(described_class.reference_pj?("Statuts\nmes-demarches: reference=Piece_Justificative")).to be true }
    it { expect(described_class.reference_pj?('Statuts')).to be false }
    it { expect(described_class.reference_pj?('mes-demarches: reference=autre')).to be false }
    it('illisible') { expect(described_class.reference_pj?("mes-demarches: a\nmes-demarches: b")).to be false }
  end

  describe '.description_table' do
    it 'rédige les deux lignes du contrat' do
      expect(described_class.description_table(mode: :dlnuf, proprietaire: 12_345)).to eq(
        "Référentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.\n" \
        'mes-demarches: referentiel=DLNUF; proprietaire=12345'
      )
    end

    it 'remplace un marqueur existant et garde le reste' do
      existante = "Numéro du dossier\nRéférentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.\nmes demarches: referentiel=archive"
      resultat = described_class.description_table(mode: :dlnuf, proprietaire: 7, existante:)
      expect(resultat.lines.map(&:chomp)).to eq(['Numéro du dossier',
                                                 'Référentiel DLNUF : lignes effacées avec leur dossier Mes-Démarches. Ne pas modifier la ligne suivante.',
                                                 'mes-demarches: referentiel=DLNUF; proprietaire=7'])
      expect(described_class.type_table(resultat)).to eq([:dlnuf, 7])
    end

    it 'retire le marqueur en archive' do
      expect(described_class.description_table(mode: :archive, existante: "Numéro du dossier\nmes-demarches: referentiel=DLNUF; proprietaire=7")).to eq('Numéro du dossier')
    end

    it 'rend une chaîne vide en archive sans autre contenu' do
      expect(described_class.description_table(mode: :archive, existante: 'mes-demarches: referentiel=DLNUF; proprietaire=7')).to eq('')
    end
  end
end
