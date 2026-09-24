# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dbs::EleveursDuLot do
  # Un FieldChecker minimal qui inclut le mixin, pour exercer instanciate / champs_to_values réels.
  let(:hote_class) do
    Class.new(FieldChecker) do
      include Dbs::EleveursDuLot

      def process(_demarche, _dossier); end
    end
  end
  let(:hote) { hote_class.new({}) }

  def champ(label, value, typename: 'TextChamp')
    double(label, label:, __typename: typename, value:, string_value: value, int_value: value)
  end

  def row(nom, email, tel, quantite)
    double("Row #{nom}", champs: [champ("Nom et Prénom de l'éleveur", nom), champ("Email de l'éleveur", email),
                                  champ("Téléphone de l'éleveur", tel), champ('Quantité de poussins', quantite, typename: 'IntegerNumberChamp')])
  end

  let(:lieux) { double('Lieux', label: "Lieux d'isolement", __typename: 'MultipleDropDownListChamp', values: lieux_values) }
  let(:lieux_values) { ['Chez des éleveurs'] }
  let(:dossier) do
    double('Dossier', number: 654_000, usager: double('Usager', email: 'Chanel@exemple.pf'),
                      champs: [double('Bloc', label: 'Liste des éleveurs', __typename: 'RepetitionChamp',
                                              rows: [row('Manutere TERE', 'Manutere@exemple.pf', '87 54 65 75', 300)]),
                               lieux,
                               champ('Nom du responsable', 'MOLLARD'), champ('Prénom du responsable', 'Vaihere'),
                               champ('Téléphone', '40 50 60 70'),
                               champ('Quantité de poussins isolés chez vous', 700, typename: 'IntegerNumberChamp')],
                      annotations: [])
  end
  let(:cfg) do
    { eleveurs: 'Liste des éleveurs', nom_eleveur: "Nom et Prénom de l'éleveur", email_eleveur: "Email de l'éleveur",
      telephone_eleveur: "Téléphone de l'éleveur", quantite_eleveur: 'Quantité de poussins',
      importateur_eleveur: { si: "Lieux d'isolement", vaut: 'Chez vous', nom: '{Prénom du responsable} {Nom du responsable}',
                             email: '{usager.email}', telephone: '{Téléphone}', quantite: '{Quantité de poussins isolés chez vous}' } }
  end

  before { hote.dossier = dossier }

  it 'rend les lignes du bloc, courriel en minuscules, valeurs par libellé' do
    liste = hote.eleveurs_du_lot(dossier, cfg)
    expect(liste.size).to eq 1
    expect(liste.first).to include(nom: 'Manutere TERE', email: 'manutere@exemple.pf', telephone: '87 54 65 75')
    expect(liste.first[:valeurs]).to include("Email de l'éleveur" => 'Manutere@exemple.pf', 'Quantité de poussins' => '300')
  end

  context "quand l'importateur isole une partie du lot chez lui" do
    let(:lieux_values) { ['Chez vous', 'Chez des éleveurs'] }

    it "ajoute en tête une ligne construite depuis le dossier de l'importateur" do
      liste = hote.eleveurs_du_lot(dossier, cfg)
      expect(liste.map { |e| e[:email] }).to eq ['chanel@exemple.pf', 'manutere@exemple.pf']
      expect(liste.first).to include(nom: 'Vaihere MOLLARD', telephone: '40 50 60 70')
      expect(liste.first[:valeurs]).to include("Nom et Prénom de l'éleveur" => 'Vaihere MOLLARD', "Email de l'éleveur" => 'chanel@exemple.pf',
                                               "Téléphone de l'éleveur" => '40 50 60 70', 'Quantité de poussins' => '700')
    end
  end

  context "quand l'importateur se liste aussi lui-même comme ligne du bloc" do
    let(:lieux_values) { ['Chez vous'] }
    let(:dossier) do
      double('Dossier', number: 654_000, usager: double('Usager', email: 'Chanel@exemple.pf'),
                        champs: [double('Bloc', label: 'Liste des éleveurs', __typename: 'RepetitionChamp',
                                                rows: [row('Vaihere MOLLARD', 'CHANEL@exemple.pf', '40 50 60 70', 700),
                                                       row('Manutere TERE', 'Manutere@exemple.pf', '87 54 65 75', 300)]),
                                 lieux,
                                 champ('Nom du responsable', 'MOLLARD'), champ('Prénom du responsable', 'Vaihere'),
                                 champ('Téléphone', '40 50 60 70'),
                                 champ('Quantité de poussins isolés chez vous', 700, typename: 'IntegerNumberChamp')],
                        annotations: [])
    end

    it "ne le liste qu'une fois, la ligne construite depuis le dossier l'emportant" do
      liste = hote.eleveurs_du_lot(dossier, cfg)
      expect(liste.map { |e| e[:email] }).to eq ['chanel@exemple.pf', 'manutere@exemple.pf']
      expect(liste.first).to include(nom: 'Vaihere MOLLARD')
    end
  end

  it "n'ajoute rien quand importateur_eleveur n'est pas configuré" do
    expect(hote.eleveurs_du_lot(dossier, cfg.except(:importateur_eleveur)).size).to eq 1
  end
end
