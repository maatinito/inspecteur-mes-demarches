# frozen_string_literal: true

module Dbs
  # Les éleveurs destinataires d'un laissez-passer : les lignes du bloc « Liste des éleveurs », plus, si
  # l'importateur isole lui-même une partie du lot (« Lieux d'isolement » contient « Chez vous »), une ligne
  # construite depuis son propre dossier — il est éleveur destinataire au même titre que les autres et ne
  # ressaisit rien. Chaque ligne porte ses valeurs par libellé de sous-champ (`valeurs`), pour que les chemins
  # `prerempli` d'InviterEleveurs s'y résolvent comme sur une vraie ligne. Mixin pour FieldChecker.
  module EleveursDuLot
    def eleveurs_du_lot(dossier, cfg)
      lignes = (dossier_field(dossier, cfg[:eleveurs], warn_if_empty: false)&.rows || []).map do |row|
        row.champs.to_h { |c| [c.label, champs_to_values([c]).first.to_s.strip] }
      end
      lignes.unshift(ligne_importateur(dossier, cfg)) if importateur_eleveur?(dossier, cfg)
      lignes = lignes.map do |valeurs|
        { nom: valeurs[cfg[:nom_eleveur]].to_s, email: valeurs[cfg[:email_eleveur]].to_s.downcase,
          telephone: valeurs[cfg[:telephone_eleveur]].to_s, valeurs: }
      end
      # L'importateur peut aussi se lister lui-même comme ligne du bloc : on ne garde que la première
      # occurrence d'un courriel (la ligne importateur est en tête, elle l'emporte). Les courriels vides ne
      # sont jamais fusionnés entre eux.
      lignes.each_with_object([]) { |e, acc| acc << e unless e[:email].present? && acc.any? { |a| a[:email] == e[:email] } }
    end

    private

    def importateur_eleveur?(dossier, cfg)
      imp = cfg[:importateur_eleveur]
      return false if imp.blank?

      champs_to_values(object_field_values(dossier, imp[:si].to_s, log_empty: false)).map(&:to_s).include?(imp[:vaut].to_s)
    end

    def ligne_importateur(dossier, cfg)
      imp = cfg[:importateur_eleveur]
      { cfg[:nom_eleveur] => instanciate(imp[:nom].to_s, dossier).strip,
        cfg[:email_eleveur] => instanciate(imp[:email].to_s, dossier).strip.downcase,
        cfg[:telephone_eleveur] => instanciate(imp[:telephone].to_s, dossier).strip,
        cfg[:quantite_eleveur] => instanciate(imp[:quantite].to_s, dossier).strip }
    end
  end
end
