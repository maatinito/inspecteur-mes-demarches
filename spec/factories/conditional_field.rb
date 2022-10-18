# frozen_string_literal: true

FactoryBot.define do
  factory :cis_association, class: ConditionalField do
    champ { 'demandeur.entreprise.forme_juridique_code' }
    valeurs do
      {
        'par défaut' => nil,
        '920' => [
          { 'mandatory_field_check' =>
              { 'message' => 'Le champ doit être rempli car le dossier concerne une association',
                'champs' => ['Statuts à jour', 'Composition du bureau', "Déclaration de l'association"] } }
        ]
      }
    end
    initialize_with { ConditionalField.new(attributes) }
  end

  factory :protocole_sanitaire, class: ConditionalField do
    champ { 'Protocole sanitaire' }
    valeurs do
      {
        'Immunisé' => [
          { 'mandatory_field_check' => {
            'message' => 'm1',
            'champs' => ["Schema d'immunisation.Document"]
          } }
        ],
        'En quarantaine' => [
          { 'mandatory_field_check' =>
              { 'message' => 'm2', 'champs' => ['Besoin médical', 'Signaler', 'Tests PCR', 'Lieu de quarantaine'] } },
          { 'conditional_field' =>
              { 'champ' => 'Lieu de quarantaine',
                'valeurs' =>
                  { 'dans votre logement' => [
                      { 'mandatory_field_check' =>
                          { 'message' => 'm3',
                            'champs' => ['Commune', 'Indications logement', "Transport depuis l'aéroport"] } }
                    ],
                    'en hôtel agréé' => [
                      { 'mandatory_field_check' =>
                          { 'message' => 'm4',
                            'champs' => ["Adresse de l'hôtel", 'Justificatif de réservation'] } }
                    ] } } }
        ]
      }
    end
    initialize_with { ConditionalField.new(attributes) }
  end
end
