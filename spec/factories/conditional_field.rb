# frozen_string_literal: true

FactoryBot.define do
  factory :protocole_sanitaire, class: ConditionalField do
    champ { 'Protocole sanitaire' }
    valeurs { {
      "Immunisé" => [
        { "mandatory_field_check" => {
          "message" => "m1",
          "champs" => ["Schema d'immunisation.Document"] } }],
      "En quarantaine" => [
        { "mandatory_field_check" =>
            { "message" => "m2", "champs" => ["Besoin médical", "Signaler", "Tests PCR", "Lieu de quarantaine"] } },
        { "conditional_field" =>
            { "champ" => "Lieu de quarantaine",
              "valeurs" =>
                { "dans votre logement" => [
                  { "mandatory_field_check" =>
                      { "message" => "m3",
                        "champs" => ["Commune", "Indications logement", "Transport depuis l'aéroport"] } }],
                  "en hôtel agréé" => [
                    { "mandatory_field_check" =>
                        { "message" => "m4",
                          "champs" => ["Adresse de l'hôtel", "Justificatif de réservation"] } }] } } }] } }
    initialize_with { ConditionalField.new(attributes) }
  end
end
