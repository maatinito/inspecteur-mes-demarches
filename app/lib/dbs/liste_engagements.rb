# frozen_string_literal: true

module Dbs
  # Les deux zones de texte du laissez-passer que le robot réécrit en entier :
  # « Engagements reçus » et « Engagements manquants ». Le format des lignes est
  # fixe : le robot l'écrit ET le relit, l'agent ne fait que lire. Une ligne
  # retouchée à la main ne correspond plus au format et disparaît à la
  # réécriture suivante — c'est voulu, la source est la liste complète.
  class ListeEngagements
    Engagement = Struct.new(:nom, :email, :numero, :date, :attendu)

    TIRET = ' — '
    NON_ATTENDU = 'non attendu'
    LIGNE_RECU = %r{\A(?<nom>.+?) \((?<email>[^)]+)\)#{TIRET}dossier (?<numero>\d+)#{TIRET}déposé le (?<date>\d{2}/\d{2}/\d{4})(?<suffixe>#{TIRET}#{NON_ATTENDU})?\z}

    def self.parse_recus(texte)
      texte.to_s.lines.map(&:strip).reject(&:blank?).filter_map do |ligne|
        m = LIGNE_RECU.match(ligne)
        next unless m

        Engagement.new(nom: m[:nom], email: m[:email].downcase, numero: m[:numero].to_i,
                       date: Date.strptime(m[:date], '%d/%m/%Y'), attendu: m[:suffixe].nil?)
      end
    end

    def self.format_recus(engagements)
      engagements.sort_by(&:numero).map do |e|
        ligne = "#{e.nom} (#{e.email})#{TIRET}dossier #{e.numero}#{TIRET}déposé le #{e.date.strftime('%d/%m/%Y')}"
        e.attendu ? ligne : "#{ligne}#{TIRET}#{NON_ATTENDU}"
      end.join("\n")
    end

    def self.upsert(engagements, nouveau)
      engagements.reject { |e| e.numero == nouveau.numero } + [nouveau]
    end

    # eleveurs : lignes du bloc « Liste des éleveurs » du laissez-passer,
    # sous la forme [{ nom:, email:, telephone: }].
    def self.format_manquants(eleveurs, engagements)
      recus = engagements.to_set { |e| e.email.downcase }
      eleveurs.reject { |e| recus.include?(e[:email].to_s.downcase) }.map do |e|
        [e[:nom], e[:telephone].presence && "au #{e[:telephone]}", "(#{e[:email]})"].compact.join(' ')
      end.join("\n")
    end
  end
end
