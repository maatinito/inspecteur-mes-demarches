# frozen_string_literal: true

FactoryBot.define do
  factory :daeth, class: Travail::Daeth do
    etat_du_dossier { 'en_construction, en_instruction' }
    champ_effectifs { "Calcul de l'assiette d'assujettissement" }
    cellule_ETP { 'D5' }
    cellule_ETP_ECAP { 'D6' }
    cellule_assiette { 'D7' }
    cellule_obligation { 'D8' }
    cellule_licenciement { 'D9' }
    champ_prestations { "Nombre d'unités d'équivalence" }
    champ_travailleurs { 'Travailleurs handicapés' }
    smig { 1111 }
    champs_par_travailleur do
      'Situation, Type de contrat, Date de début du contrat, Date de fin du contrat, Heures par semaine, ' \
        "Catégorie d'handicap, Date de début des droits COTOREP, Date de fin des droits COTOREP, Taux d'IPP, Rente ?"
    end

    initialize_with { Travail::Daeth.new(attributes) }
  end
end
