# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Travail::DaethRepartition do
  let(:instructeur) { 'instructeur' }
  let(:demarche) { double(Demarche, instructeur:) }
  let(:state) { 'accepte' }
  let(:dossier) { Struct.new(:number, :state, :date_depot).new(438_520, state, Date.new(2026, 2, 1)) }
  let(:controle) { FactoryBot.build :daeth_repartition }

  let(:annee) { { cotorep_begin: DateValue.new(2025, 1, 1), cotorep_end: DateValue.new(2026, 1, 1) } }
  let(:statut_a) { 'FPT' }
  let(:cadre_a) { 'A - Ingénieur' }
  let(:worker_a) do
    { status: Travail::Daeth::STATUS_COTOREP, contract_type: statut_a, category: cadre_a, cotorep_category: 'B' }.merge(annee)
  end
  let(:worker_b) do
    { status: Travail::Daeth::STATUS_COTOREP, contract_type: 'FPT', category: 'B - Technicien', cotorep_category: 'C' }.merge(annee)
  end
  let(:worker_c) do
    { status: Travail::Daeth::STATUS_COTOREP, contract_type: 'ANT', category: 'AN3 - CC3', cotorep_category: 'A',
      contract_begin: DateValue.new(2025, 7, 1) }.merge(annee)
  end
  # Accident du travail sans rente : 0 unité, donc exclu des deux blocs.
  let(:worker_d) do
    { status: Travail::Daeth::STATUS_PDD, contract_type: 'FPT', category: 'C - Agent technique', pdd_rate: 30, annuity: false }
  end
  let(:worker_e) do
    { status: Travail::Daeth::STATUS_PENSION, contract_type: 'ANFA, PNNIM, ENIM, DI, SR, AVOC', category: 'AN5 - CC5' }
  end
  let(:disabled_workers) { [worker_a, worker_b, worker_c, worker_d, worker_e] }

  # Valeurs d'une mesure : les quatre lignes de statut, puis « Non classé ».
  def bloc(_titre, *lignes, non_classe: '0')
    [lignes, non_classe]
  end

  def texte((etp, etp_non_classe), (unites, unites_non_classe))
    ['Statut ; ETP A ; B ; C ; D | Unités A ; B ; C ; D',
     *['FPT', 'FPT stagiaire', 'ANFA', 'ANT'].each_with_index.map { |statut, i| "#{statut} ; #{etp[i]} | #{unites[i]}" },
     "Non classé ; #{etp_non_classe} | #{unites_non_classe}"].join("\n")
  end

  let(:zeros) { '0 ; 0 ; 0 ; 0' }

  describe 'configuration' do
    it "n'exige aucun paramètre de cellule Excel" do
      expect(controle.errors).to be_empty
      expect(controle.valid?).to be_truthy
    end

    it 'refuse une configuration sans champ_categorie' do
      controle = described_class.new(FactoryBot.attributes_for(:daeth_repartition).except(:champ_categorie))
      expect(controle.valid?).to be_falsey
      expect(controle.errors.first).to include('champ_categorie')
    end
  end

  describe '#disabled_workers' do
    it "lit le cadre d'emplois dans la ligne du bloc" do
      champ = ->(label, value) { double(label, label:, __typename: 'TextChamp', value:) }
      row = double('Row', champs: [champ.call('Situation', Travail::Daeth::STATUS_PENSION), champ.call('Statut', 'FPT'),
                                   champ.call("Catégorie et cadre d'emplois ou équivalent", 'A - Ingénieur')])
      allow(controle).to receive(:declaration_year).and_return(2025)
      allow(controle).to receive(:param_field).and_return(double('Bloc', rows: [row]))

      expect(controle.disabled_workers.first).to include(contract_type: 'FPT', category: 'A - Ingénieur')
    end
  end

  describe '#process' do
    before do
      allow(controle).to receive(:declared_year).and_return(2025)
      allow(controle).to receive(:disabled_workers).and_return(disabled_workers)
      allow(SetAnnotationValue).to receive(:set_value).and_return(false)
    end

    subject { controle.process(demarche, dossier) }

    it 'écrit les deux mesures côte à côte, la catégorie de handicap C comptant double dans les unités' do
      subject
      expect(SetAnnotationValue).to have_received(:set_value).with(
        dossier, instructeur, 'Détails des bénéficiaires',
        "Statut ; ETP A ; B ; C ; D | Unités A ; B ; C ; D\n" \
        "FPT ; 1 ; 1 ; 0 ; 0 | 1 ; 2 ; 0 ; 0\n" \
        "FPT stagiaire ; 0 ; 0 ; 0 ; 0 | 0 ; 0 ; 0 ; 0\n" \
        "ANFA ; 0 ; 0 ; 0 ; 1 | 0 ; 0 ; 0 ; 1\n" \
        "ANT ; 0 ; 0 ; 0,504 ; 0 | 0 ; 0 ; 0,504 ; 0\n" \
        'Non classé ; 0 | 0'
      )
    end

    it "n'écrit aucune autre annotation" do
      subject
      expect(SetAnnotationValue).to have_received(:set_value).once
    end

    context 'avec un travailleur au statut vide' do
      let(:statut_a) { nil }

      it 'le range en « Non classé »' do
        subject
        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier, instructeur, 'Détails des bénéficiaires',
          texte(bloc('ETP', '0 ; 1 ; 0 ; 0', zeros, '0 ; 0 ; 0 ; 1', '0 ; 0 ; 0,504 ; 0', non_classe: '1'),
                bloc('Unités', '0 ; 2 ; 0 ; 0', zeros, '0 ; 0 ; 0 ; 1', '0 ; 0 ; 0,504 ; 0', non_classe: '1'))
        )
      end
    end

    context "avec un cadre d'emplois inconnu" do
      let(:cadre_a) { 'Z - Inconnu' }

      it 'le range en « Non classé »' do
        subject
        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier, instructeur, 'Détails des bénéficiaires',
          texte(bloc('ETP', '0 ; 1 ; 0 ; 0', zeros, '0 ; 0 ; 0 ; 1', '0 ; 0 ; 0,504 ; 0', non_classe: '1'),
                bloc('Unités', '0 ; 2 ; 0 ; 0', zeros, '0 ; 0 ; 0 ; 1', '0 ; 0 ; 0,504 ; 0', non_classe: '1'))
        )
      end
    end

    context 'sans travailleur' do
      let(:disabled_workers) { [] }

      it 'écrit une grille de zéros' do
        subject
        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier, instructeur, 'Détails des bénéficiaires',
          texte(bloc('ETP', zeros, zeros, zeros, zeros), bloc('Unités', zeros, zeros, zeros, zeros))
        )
      end
    end

    context "quand l'annotation est absente du dossier (dossier clos non rebasé)" do
      before do
        allow(SetAnnotationValue).to receive(:set_value).and_raise("Unable to find annotation 'Détails des bénéficiaires' on dossier 438520")
      end

      it 'journalise le dossier et continue' do
        expect(Rails.logger).to receive(:error).with(/438520/)
        expect { subject }.not_to raise_error
      end
    end

    context "quand l'écriture échoue pour une autre raison" do
      before { allow(SetAnnotationValue).to receive(:set_value).and_raise('HTTP 502') }

      it "laisse remonter l'erreur, pour que le dossier soit rejoué" do
        expect { subject }.to raise_error('HTTP 502')
      end
    end

    # La somme des unités doit retomber sur « ETP Bénéficiaires » : même
    # arrondi unique que Daeth#disabled_worker_fte, et non un arrondi de la
    # présence suivi d'un arrondi du produit (1,002 au lieu de 1,003 ici).
    context 'avec un poids 2 sur une présence partielle' do
      let(:worker_c) do
        { status: Travail::Daeth::STATUS_COTOREP, contract_type: 'ANT', category: 'AN3 - CC3', cotorep_category: 'C',
          contract_begin: DateValue.new(2025, 7, 2) }.merge(annee)
      end
      let(:disabled_workers) { [worker_c] }

      it 'arrondit les unités comme Daeth' do
        expect(controle).to receive(:declaration_year).at_least(:once).and_return(2025)
        subject
        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier, instructeur, 'Détails des bénéficiaires',
          texte(bloc('ETP', zeros, zeros, zeros, '0 ; 0 ; 0,501 ; 0'), bloc('Unités', zeros, zeros, zeros, '0 ; 0 ; 1,003 ; 0'))
        )
        expect(controle.disabled_worker_fte).to eq(1.003)
      end
    end

    context "avec une date de sortie antérieure à la date d'entrée" do
      let(:worker_c) do
        { status: Travail::Daeth::STATUS_COTOREP, contract_type: 'ANT', category: 'AN3 - CC3', cotorep_category: 'A',
          contract_begin: DateValue.new(2025, 6, 1), contract_end: DateValue.new(2025, 3, 1) }.merge(annee)
      end
      let(:disabled_workers) { [worker_c] }

      it "n'écrit pas de valeur négative" do
        subject
        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier, instructeur, 'Détails des bénéficiaires',
          texte(bloc('ETP', zeros, zeros, zeros, zeros), bloc('Unités', zeros, zeros, zeros, zeros))
        )
      end
    end

    context "quand l'année déclarée n'est pas l'année précédente" do
      before { allow(controle).to receive(:declared_year).with(nil).and_return(2023) }
      let(:disabled_workers) { [worker_c] }

      it "calcule sur l'année déclarée du dossier" do
        subject
        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier, instructeur, 'Détails des bénéficiaires',
          texte(bloc('ETP', zeros, zeros, zeros, zeros), bloc('Unités', zeros, zeros, zeros, zeros))
        )
      end
    end

    context "quand l'annotation est absente d'un dossier encore en instruction" do
      let(:state) { 'en_instruction' }

      before do
        allow(SetAnnotationValue).to receive(:set_value).and_raise("Unable to find annotation 'Détails des bénéficiaires' on dossier 438520")
      end

      it "laisse remonter l'erreur : c'est une erreur de configuration" do
        expect { subject }.to raise_error(/Unable to find annotation/)
      end
    end

    context 'hors des états configurés' do
      let(:state) { 'en_construction' }

      it 'ne fait rien' do
        subject
        expect(SetAnnotationValue).not_to have_received(:set_value)
      end
    end
  end
end
