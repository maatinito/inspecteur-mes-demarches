#!/usr/bin/env ruby
# frozen_string_literal: true

# Script pour compter les dossiers en_instruction affectés par le changement civilités
# À exécuter en production : ruby count_civilite_impact.rb

require_relative 'config/environment'

# Démarches concernées par le changement civilités (avec set_field utilisant {civilite})
DEMARCHES_CONCERNEES = {
  'DAF TOMITE' => 2996,
  'DBS Laissez-Passer' => [1995, 2439],
  'DIREN Signalements' => 3091
}.freeze

puts '=' * 80
puts "ANALYSE D'IMPACT - Changement civilités (M./Mme → Monsieur/Madame)"
puts '=' * 80
puts ''

total_dossiers = 0
total_avec_civilite = 0

DEMARCHES_CONCERNEES.each do |name, demarche_ids|
  demarche_ids = [demarche_ids] unless demarche_ids.is_a?(Array)

  demarche_ids.each do |demarche_id|
    puts "--- #{name} (ID: #{demarche_id}) ---"

    begin
      # Définir la requête GraphQL
      GetDossiersEnInstruction = MesDemarches::Client.parse <<~GRAPHQL
        query($demarcheNumber: Int!, $state: DossierState!) {
          demarche(number: $demarcheNumber) {
            dossiers(state: $state) {
              pageInfo {
                hasPreviousPage
                hasNextPage
              }
              nodes {
                number
                state
                demandeur {
                  ... on PersonnePhysique {
                    civilite
                    nom
                    prenom
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      result = MesDemarches.query(
        GetDossiersEnInstruction,
        variables: {
          demarcheNumber: demarche_id,
          state: 'en_instruction'
        }
      )

      if result.errors.present?
        puts "  ❌ Erreur API: #{result.errors.messages.inspect}"
        next
      end

      dossiers = result.data.demarche.dossiers.nodes
      nb_dossiers = dossiers.count
      total_dossiers += nb_dossiers

      # Compter les dossiers avec civilité
      dossiers_avec_civilite = dossiers.select do |d|
        d.demandeur&.civilite.present?
      end
      nb_avec_civilite = dossiers_avec_civilite.count
      total_avec_civilite += nb_avec_civilite

      # Répartition par civilité
      repartition = dossiers_avec_civilite.group_by { |d| d.demandeur.civilite }
                                          .transform_values(&:count)

      puts "  📊 Dossiers en_instruction: #{nb_dossiers}"
      puts "  👤 Avec civilité: #{nb_avec_civilite}"

      if nb_avec_civilite.positive?
        puts '  📈 Répartition:'
        repartition.each do |civilite, count|
          nouveau_format = case civilite
                           when 'M.', 'M' then 'Monsieur'
                           when 'Mme', 'Mlle' then 'Madame'
                           else civilite
                           end
          puts "     - #{civilite} → #{nouveau_format}: #{count} dossiers"
        end
      end

      # Warning si pagination
      puts '  ⚠️  ATTENTION: Il y a plus de dossiers (pagination non gérée)' if result.data.demarche.dossiers.pageInfo.hasNextPage
    rescue StandardError => e
      puts "  ❌ Erreur: #{e.message}"
      puts "     #{e.backtrace.first}"
    end

    puts ''
  end
end

puts '=' * 80
puts 'SYNTHÈSE'
puts '=' * 80
puts "Total dossiers en_instruction: #{total_dossiers}"
puts "Total avec civilité (à régénérer): #{total_avec_civilite}"
puts ''

if total_avec_civilite.positive?
  puts '⚠️  IMPACT ESTIMÉ:'
  puts "   - #{total_avec_civilite} documents seront régénérés automatiquement"
  puts '   - Les instructeurs verront de nouvelles versions'
  puts '   - Seule différence: civilités en toutes lettres'
  puts ''

  if total_avec_civilite < 10
    puts '✅ FAIBLE: Déploiement recommandé avec communication préventive'
  elsif total_avec_civilite < 50
    puts '🟠 MOYEN: Déploiement possible, informer les instructeurs'
  else
    puts '🔴 ÉLEVÉ: Envisager un déploiement progressif ou attendre'
  end
else
  puts '✅ AUCUN IMPACT: Pas de dossiers en cours avec civilités'
end
