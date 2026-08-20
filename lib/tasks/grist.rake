# frozen_string_literal: true

namespace :grist do
  desc "Purge les lignes héritées d'une table liée — celles dépourvues de numéro de ligne — pour les " \
       'seuls parents que le robot a déjà recopiés ' \
       '(rake "grist:purger_sans_ligne[doc_id,table,colonne_ligne,pour_de_vrai,colonne_parent]")'
  task :purger_sans_ligne, %i[doc_id table colonne_ligne pour_de_vrai colonne_parent] => :environment do |_task, args|
    doc_id = args[:doc_id]
    table_id = args[:table]
    colonne_ligne = args[:colonne_ligne].presence || 'Ligne'
    colonne_parent = args[:colonne_parent].presence || 'Dossier'
    simulation = args[:pour_de_vrai].to_s != 'oui'

    abort 'Usage : rake "grist:purger_sans_ligne[doc_id,table,Ligne,oui]"' if doc_id.blank? || table_id.blank?

    table = Grist::Config.table(doc_id, table_id)

    unless table.columns.key?(colonne_ligne)
      abort "La colonne #{colonne_ligne} n'existe pas dans #{table_id} : rien à purger " \
            '(créez-la avant de faire tourner le plugin).'
    end

    # Sans colonne de rattachement, un doublon est indiscernable d'une unique
    # copie : la tâche s'arrête plutôt que de purger à l'aveugle.
    unless table.columns.key?(colonne_parent)
      abort "La colonne #{colonne_parent} n'existe pas dans #{table_id} : le garde-fou ne peut pas établir " \
            "quels #{colonne_parent} ont été recopiés (passez la bonne colonne en 5e argument)."
    end

    records = table.list_records['records'] || []

    # Une valeur de référence vide vaut 0 côté Grist, et non nil : 0 n'étant pas
    # `blank?` en Ruby, il faut l'écarter explicitement — sans quoi toutes les
    # lignes non rattachées seraient regroupées sous un même faux parent.
    valeur = lambda do |record, colonne|
      brut = record.dig('fields', colonne)
      brut.present? && brut.to_s != '0' ? brut : nil
    end

    # Le numéro de ligne est la signature du robot : seul un upsert par
    # (parent, Ligne) le renseigne. Une ligne héritée de n8n en est dépourvue, et
    # ni la clé d'upsert ni la suppression des orphelins ne peuvent l'atteindre —
    # elle resterait indéfiniment à côté des lignes recopiées.
    recopiees, heritees = records.partition { |r| valeur.call(r, colonne_ligne) }

    # GARDE-FOU : une ligne héritée n'est un doublon que si son parent porte déjà
    # au moins une ligne recopiée. Sinon elle est la seule copie de la donnée, et
    # sa suppression serait une perte sèche — cas d'un parent jamais rejoué, ou
    # rejoué en vain parce que son fichier source est absent ou illisible.
    parents_repris = recopiees.filter_map { |r| valeur.call(r, colonne_parent) }.to_set

    purgeables, conservees = heritees.partition do |r|
      (id = valeur.call(r, colonne_parent)) && parents_repris.include?(id)
    end
    orphelines = conservees.count { |r| valeur.call(r, colonne_parent).nil? }
    parents_purges = purgeables.filter_map { |r| valeur.call(r, colonne_parent) }.uniq.size

    puts "Table #{table_id} : #{records.size} ligne(s), dont #{heritees.size} sans #{colonne_ligne}."
    puts "  #{purgeables.size} purgeable(s) : #{parents_purges} #{colonne_parent}(s) déjà recopié(s) par le robot."
    puts "  #{conservees.size} conservée(s) : #{conservees.size - orphelines} sur un #{colonne_parent} " \
         "pas encore recopié, #{orphelines} sans #{colonne_parent}."

    if purgeables.empty?
      puts 'Rien à purger.'
      next
    end

    apercu = purgeables.first(3).map { |r| r['id'] }.join(', ')
    puts "Premiers ids concernés : #{apercu}#{'…' if purgeables.size > 3}"

    if simulation
      puts
      puts 'SIMULATION — aucune suppression effectuée.'
      puts "Pour supprimer réellement : rake \"grist:purger_sans_ligne[#{doc_id},#{table_id}," \
           "#{colonne_ligne},oui,#{colonne_parent}]\""
      next
    end

    # Suppression par lots : un seul appel portant des milliers d'ids serait
    # refusé ou trop lourd.
    supprimees = 0
    purgeables.each_slice(500) do |lot|
      table.delete_records(lot.map { |r| r['id'] })
      supprimees += lot.size
      puts "  #{supprimees}/#{purgeables.size} supprimée(s)…"
    end

    puts "Terminé : #{supprimees} ligne(s) supprimée(s)."
  end
end
