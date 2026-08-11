# frozen_string_literal: true

namespace :grist do
  desc "Purge les lignes d'une table liée dépourvues de numéro de ligne " \
       '(rake "grist:purger_sans_ligne[doc_id,table,colonne_ligne,pour_de_vrai]")'
  task :purger_sans_ligne, %i[doc_id table colonne_ligne pour_de_vrai] => :environment do |_task, args|
    doc_id = args[:doc_id]
    table_id = args[:table]
    colonne_ligne = args[:colonne_ligne].presence || 'Ligne'
    simulation = args[:pour_de_vrai].to_s != 'oui'

    abort 'Usage : rake "grist:purger_sans_ligne[doc_id,table,Ligne,oui]"' if doc_id.blank? || table_id.blank?

    table = Grist::Config.table(doc_id, table_id)

    unless table.columns.key?(colonne_ligne)
      abort "La colonne #{colonne_ligne} n'existe pas dans #{table_id} : rien à purger " \
            '(créez-la avant de faire tourner le plugin).'
    end

    records = table.list_records['records'] || []
    # Une ligne héritée de n8n n'a pas de numéro de ligne : ni la clé d'upsert
    # (Dossier, Ligne) ni la suppression des orphelins ne peuvent l'atteindre.
    # Elle resterait indéfiniment à côté des lignes recopiées par le robot.
    orphelines = records.select { |r| r.dig('fields', colonne_ligne).blank? }

    puts "Table #{table_id} : #{records.size} ligne(s), dont #{orphelines.size} sans #{colonne_ligne}."

    if orphelines.empty?
      puts 'Rien à purger.'
      next
    end

    apercu = orphelines.first(3).map { |r| r['id'] }.join(', ')
    puts "Premiers ids concernés : #{apercu}#{'…' if orphelines.size > 3}"

    if simulation
      puts
      puts 'SIMULATION — aucune suppression effectuée.'
      puts "Pour supprimer réellement : rake \"grist:purger_sans_ligne[#{doc_id},#{table_id},#{colonne_ligne},oui]\""
      next
    end

    # Suppression par lots : un seul appel portant des milliers d'ids serait
    # refusé ou trop lourd.
    supprimees = 0
    orphelines.each_slice(500) do |lot|
      table.delete_records(lot.map { |r| r['id'] })
      supprimees += lot.size
      puts "  #{supprimees}/#{orphelines.size} supprimée(s)…"
    end

    puts "Terminé : #{supprimees} ligne(s) supprimée(s)."
  end
end
