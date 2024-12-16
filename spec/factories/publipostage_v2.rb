# frozen_string_literal: true

FactoryBot.define do
  factory :publipostage_v2, class: PublipostageV2 do
    etat_du_dossier { %w[en_construction en_instruction] }
    message { 'message {number}' }
    modele { 'publipostage_v2.docx' }
    nom_fichier_lot { 'publipostage {number} {horodatage}-{lot}' }
    nom_fichier { 'publipostage v2 {number}' }
    champs { ['Navire', "Date d'arrivée", 'Produits 1', 'Produits 2'] }

    trait :docx do
      type_de_document { 'docx' }
    end

    trait :store_to_field do
      champ_cible { 'publipostage' }
    end

    trait :model_with_errors do
      modele { 'publipostage_v2_with_errors.docx' }
    end

    # trait :model_spjp do
    #   modele { 'spjp.docx' }
    #   champ_cible { 'Convention' }
    #   champs do
    #     [
    #       'Dates réservées',
    #       'Demandeur',
    #       "Description de l'événement",
    #       'Montant HT',
    #       "Nature de l'évènement",
    #       'Nombre de personnes',
    #       'Non lucratif',
    #       'Site choisi',
    #       'Sites réservés avec électricité',
    #       'Sites réservés sans électricité',
    #       "Type d'évènement",
    #       { 'colonne' => 'Date de dépôt', 'champ' => 'date_depot' },
    #       { 'colonne' => 'Date de passage en instruction', 'champ' => 'date_passage_en_instruction' },
    #       { 'colonne' => 'Dossier', 'champ' => 'number' }
    #     ]
    #   end
    # end

    trait :with_multiple_sheets do
      calculs { [{ 'excel/get_sheets' => { 'champ' => 'Produits 1' } }] }
    end

    initialize_with { PublipostageV2.new(attributes) }
  end
end
