# frozen_string_literal: true

FactoryBot.define do
  factory :dead_line_checker, class: DeadLineChecker do
    annotation_alertes { 'Historique alertes délai' }
    recevabilite do
      {
        'duree_max' => 15,
        'annotation_jours_restants' => 'Jours restants recevabilité',
        'seuils' => [
          { 'jours' => 5, 'alerter' => 'chef@admin.gov.pf', 'objet' => 'Alerte {phase}', 'message' => '{jours_restants}j restants' }
        ]
      }
    end
    instruction do
      {
        'duree_max' => 60,
        'annotation_jours_restants' => 'Jours restants instruction',
        'seuils' => [
          { 'jours' => 10, 'alerter' => 'chef@admin.gov.pf', 'objet' => 'Alerte {phase}', 'message' => '{jours_restants}j restants' }
        ]
      }
    end

    trait :recevabilite_only do
      instruction { nil }
    end

    trait :instruction_only do
      recevabilite { nil }
    end

    trait :without_phases do
      recevabilite { nil }
      instruction { nil }
    end

    initialize_with { DeadLineChecker.new(attributes) }
  end
end
