# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::ReferencesLaissezPasser do
  let(:params) do
    { 'eleveurs' => 'Liste des élevages destinataires', 'engagements_recus' => 'Engagements reçus',
      'certificats' => 'Certificats sanitaires reçus' }
  end
  let(:calcul) { described_class.new(params) }
  let(:dossier) do
    double('dossier', date_depot: '2026-10-01T09:02:00-10:00',
                      demandeur: double('demandeur', entreprise: double('entreprise', raison_sociale: 'TAMARU FARM')))
  end
  let(:eleveurs) do
    [{ nom: 'Sébastien MOLLARD', email: 'seb@ferme.pf', valeurs: { "Nom de l'élevage" => '' } },
     { nom: 'Jean DUPONT', email: 'jean@dupont.pf', valeurs: { "Nom de l'élevage" => 'Ferme Dupont' } }]
  end
  let(:engagements_recus) do
    "Jean DUPONT (jean@dupont.pf) — dossier 680145 — déposé le 01/10/2026\n" \
      'Sébastien MOLLARD (seb@ferme.pf) — dossier 680123 — déposé le 30/09/2026'
  end
  let(:valeurs) do
    { 'Quantité totale' => '1398', 'Destination des poussins' => 'Chair', 'Race ponte' => '', 'Race chair' => 'ROSS 308',
      'Provenance' => 'Nouvelle-Zélande', 'Pays de provenance' => '' }
  end
  let(:ligne_certificat) do
    { 'Désignation des poussins' => '', 'Nombre de poussins' => '', 'Numéro du certificat sanitaire' => '09876731',
      'Numéro de LTA' => '086-65271430', 'Nombre de colis' => '16' }
  end
  let(:lignes) { [ligne_certificat] }

  subject do
    result = {}
    calcul.process_row(dossier, result)
    result
  end

  before do
    allow(calcul).to receive(:eleveurs_du_lot).and_return(eleveurs)
    allow(calcul).to receive(:valeur) { |_dossier, libelle| valeurs.fetch(libelle, '') }
    allow(calcul).to receive(:texte_annotation).and_return(engagements_recus)
    allow(calcul).to receive(:lignes_certificats).and_return(lignes)
  end

  it 'is valid with its three required fields' do
    expect(calcul.errors).to be_empty
  end

  it 'lists every destinataire with his élevage, the raison sociale standing for an empty one' do
    expect(subject['Destinataires']).to eq 'Sébastien MOLLARD (TAMARU FARM) ; Jean DUPONT (Ferme Dupont)'
  end

  describe "certificats d'isolement" do
    it 'gives one numbered reference per engagement reçu, from 6/, ordered by dossier number' do
      expect(subject["Certificats d'isolement"]).to eq [
        { 'rang' => 6, 'numero' => 680_123, 'date' => '30/09/2026', 'site' => 'TAMARU FARM', 'fin' => ' ;' },
        { 'rang' => 7, 'numero' => 680_145, 'date' => '01/10/2026', 'site' => 'Ferme Dupont', 'fin' => '' }
      ]
    end

    context 'with an engagement that matches no destinataire' do
      let(:engagements_recus) { 'Paul INCONNU (paul@x.pf) — dossier 680200 — déposé le 01/10/2026 — non attendu' }

      it 'falls back on the name written in the engagement' do
        expect(subject["Certificats d'isolement"].first['site']).to eq 'Paul INCONNU'
      end
    end
  end

  describe 'articles du tableau' do
    it 'fills the single usual line from the importer data' do
      expect(subject['Articles']).to eq [
        { 'nombre' => '1398', 'designation' => 'poussins de chair de race ROSS 308', 'pays' => 'Nouvelle-Zélande',
          'certificat' => '09876731', 'colis' => '16' }
      ]
    end

    context 'with several detailed certificates' do
      let(:lignes) do
        [ligne_certificat.merge('Nombre de poussins' => '1040'),
         ligne_certificat.merge('Désignation des poussins' => 'poussins parentaux de chair de race ROSS 308',
                                'Nombre de poussins' => '358', 'Numéro du certificat sanitaire' => '09876730',
                                'Numéro de LTA' => '086-65271426', 'Nombre de colis' => '6')]
      end

      it 'keeps the agent details, defaulting only the empty désignation' do
        expect(subject['Articles'].map { |a| [a['nombre'], a['designation'], a['certificat']] }).to eq [
          ['1040', 'poussins de chair de race ROSS 308', '09876731'],
          ['358', 'poussins parentaux de chair de race ROSS 308', '09876730']
        ]
      end

      it 'joins the distinct LTA numbers' do
        expect(subject['LTA']).to eq '086-65271430, 086-65271426'
      end
    end

    context 'without any certificate recorded yet' do
      let(:lignes) { [] }

      it 'still prints one line from the importer data' do
        expect(subject['Articles'].size).to eq 1
        expect(subject['Articles'].first['nombre']).to eq '1398'
      end
    end

    context 'from another country' do
      let(:valeurs) { super().merge('Provenance' => 'Autre pays', 'Pays de provenance' => 'Australie') }

      it 'uses that country as origin' do
        expect(subject["Pays d'origine"]).to eq 'Australie'
        expect(subject['Articles'].first['pays']).to eq 'Australie'
      end
    end
  end

  it 'gives the filing date, day only' do
    expect(subject['Date de la demande']).to eq '01/10/2026'
  end

  context 'without required fields' do
    let(:params) { {} }

    it 'reports them' do
      expect(calcul.errors.join).to include('eleveurs')
    end
  end
end
