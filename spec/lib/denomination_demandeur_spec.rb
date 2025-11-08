# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Metrics/BlockLength
RSpec.describe DenominationDemandeur do
  let(:demarche) { double('Demarche', instructeur: 'instructeur_id') }
  let(:annotation_cible) { 'Dénomination demandeur' }
  let(:checker) { described_class.new({ annotation_cible: }) }

  describe '#process' do
    context 'avec une PersonneMorale' do
      let(:entreprise) do
        double('Entreprise',
               forme_juridique: 'Association de loi 1901 ou assimilé',
               raison_sociale: 'Association Les Amis de Tahiti')
      end
      let(:demandeur) do
        double('PersonneMorale',
               __typename: 'PersonneMorale',
               entreprise:)
      end
      let(:dossier) do
        double('Dossier',
               number: 12_345,
               state: 'en_construction',
               demandeur:)
      end

      before do
        allow(SetAnnotationValue).to receive(:set_value).and_return(true)
        allow(checker).to receive(:must_check?).and_return(true)
      end

      it 'génère la forme grammaticale correcte' do
        checker.process(demarche, dossier)

        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier,
          'instructeur_id',
          annotation_cible,
          "l'association Association Les Amis de Tahiti"
        )
      end
    end

    context 'avec une PersonneMorale SARL' do
      let(:entreprise) do
        double('Entreprise',
               forme_juridique: 'Société A Responsabilité Limitée ou S.A.R.L.',
               raison_sociale: 'PACIFIC TECH')
      end
      let(:demandeur) do
        double('PersonneMorale',
               __typename: 'PersonneMorale',
               entreprise:)
      end
      let(:dossier) do
        double('Dossier',
               number: 12_346,
               state: 'en_construction',
               demandeur:)
      end

      before do
        allow(SetAnnotationValue).to receive(:set_value).and_return(true)
        allow(checker).to receive(:must_check?).and_return(true)
      end

      it 'génère la forme grammaticale correcte' do
        checker.process(demarche, dossier)

        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier,
          'instructeur_id',
          annotation_cible,
          'la S.A.R.L. PACIFIC TECH'
        )
      end
    end

    context 'avec une PersonnePhysique (M.)' do
      let(:demandeur) do
        double('PersonnePhysique',
               __typename: 'PersonnePhysique',
               civilite: 'M.',
               prenom: 'Jean',
               nom: 'Dupont')
      end
      let(:dossier) do
        double('Dossier',
               number: 12_347,
               state: 'en_construction',
               demandeur:)
      end

      before do
        allow(SetAnnotationValue).to receive(:set_value).and_return(true)
        allow(checker).to receive(:must_check?).and_return(true)
      end

      it 'transforme M. en Monsieur' do
        checker.process(demarche, dossier)

        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier,
          'instructeur_id',
          annotation_cible,
          'Monsieur Jean Dupont'
        )
      end
    end

    context 'avec une PersonnePhysique (Mme)' do
      let(:demandeur) do
        double('PersonnePhysique',
               __typename: 'PersonnePhysique',
               civilite: 'Mme',
               prenom: 'Marie',
               nom: 'Martin')
      end
      let(:dossier) do
        double('Dossier',
               number: 12_348,
               state: 'en_construction',
               demandeur:)
      end

      before do
        allow(SetAnnotationValue).to receive(:set_value).and_return(true)
        allow(checker).to receive(:must_check?).and_return(true)
      end

      it 'transforme Mme en Madame' do
        checker.process(demarche, dossier)

        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier,
          'instructeur_id',
          annotation_cible,
          'Madame Marie Martin'
        )
      end
    end

    context 'avec champ_source spécifié' do
      let(:checker_with_source) { described_class.new({ annotation_cible:, champ_source: 'Numéro TAHITI' }) }
      let(:entreprise) do
        double('Entreprise',
               forme_juridique: 'Société par Actions Simplifiées ou S.A.S.',
               raison_sociale: 'INNOVATION SARL')
      end
      let(:etablissement) do
        double('Etablissement',
               __typename: 'Etablissement',
               entreprise:)
      end
      let(:champ_tahiti) do
        double('ChampTahiti',
               etablissement:)
      end
      let(:dossier) do
        double('Dossier',
               number: 12_349,
               state: 'en_construction')
      end

      before do
        allow(SetAnnotationValue).to receive(:set_value).and_return(true)
        allow(checker_with_source).to receive(:must_check?).and_return(true)
        allow(checker_with_source).to receive(:param_field).with(:champ_source).and_return(champ_tahiti)
      end

      it 'utilise le champ TAHITI au lieu du demandeur' do
        checker_with_source.process(demarche, dossier)

        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier,
          'instructeur_id',
          annotation_cible,
          'la S.A.S. INNOVATION SARL'
        )
      end
    end

    context 'avec forme juridique inconnue' do
      let(:entreprise) do
        double('Entreprise',
               forme_juridique: 'Forme Inconnue',
               raison_sociale: 'ENTREPRISE XYZ')
      end
      let(:demandeur) do
        double('PersonneMorale',
               __typename: 'PersonneMorale',
               entreprise:)
      end
      let(:dossier) do
        double('Dossier',
               number: 12_350,
               state: 'en_construction',
               demandeur:)
      end

      before do
        allow(SetAnnotationValue).to receive(:set_value).and_return(true)
        allow(checker).to receive(:must_check?).and_return(true)
        allow(Rails.logger).to receive(:warn)
      end

      it 'utilise seulement la raison sociale et logue un warning' do
        checker.process(demarche, dossier)

        expect(Rails.logger).to have_received(:warn).with('Forme juridique inconnue: Forme Inconnue')
        expect(SetAnnotationValue).to have_received(:set_value).with(
          dossier,
          'instructeur_id',
          annotation_cible,
          'ENTREPRISE XYZ'
        )
      end
    end

    context 'avec données manquantes' do
      let(:demandeur) { nil }
      let(:dossier) do
        double('Dossier',
               number: 12_351,
               state: 'en_construction',
               demandeur:)
      end

      before do
        allow(SetAnnotationValue).to receive(:set_value)
        allow(checker).to receive(:must_check?).and_return(true)
        allow(Rails.logger).to receive(:warn)
        allow(Rails.logger).to receive(:info)
      end

      it 'ne modifie pas l\'annotation et logue un warning' do
        checker.process(demarche, dossier)

        expect(Rails.logger).to have_received(:warn).with('Unable to generate denomination for dossier 12351')
        expect(SetAnnotationValue).not_to have_received(:set_value)
      end
    end
  end

  describe '#generate_denomination' do
    let(:checker) { described_class.new({ annotation_cible: 'Test' }) }

    context 'teste plusieurs formes juridiques' do
      {
        'Artisan' => "l'entreprise d'artisanat",
        'Commerçant' => "l'entreprise",
        'Auto-entrepreneur' => "l'entreprise individuelle de",
        'SARL unipersonnelle (dont E.U.R.L.)' => "l'E.U.R.L.",
        "Société Anonyme à Conseil d'Administration" => 'la S.A.',
        'Groupement d\'Intérêt Economique ou G.I.E.' => 'le G.I.E.',
        'Société Civile Immobilière (SCI)' => 'la S.C.I.',
        'Association de loi 1901 ou assimilé' => "l'association",
        'Fondation' => 'la fondation',
        'Organisme Mutualiste' => "l'organisme mutualiste"
      }.each do |forme, article_type|
        it "génère correctement pour #{forme}" do
          entreprise = double('Entreprise', forme_juridique: forme, raison_sociale: 'TEST')
          personne = double('PersonneMorale', __typename: 'PersonneMorale', entreprise:)

          result = checker.send(:generate_denomination, personne)

          expect(result).to eq("#{article_type} TEST")
        end
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength
