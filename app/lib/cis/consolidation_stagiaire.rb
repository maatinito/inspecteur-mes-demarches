# frozen_string_literal: true

module Cis
  class ConsolidationStagiaire < Consolidation
    def version
      super + 21
    end

    def required_fields
      super + %i[demarches_oa champ_oa]
    end

    def initialize(params)
      super
      @demarches_oa = Set.new(@params[:demarches_oa])
    end

    def check(dossier)
      @dossier_oa = dossier_oa
      return unless @dossier_oa.present?

      candidats = candidats(@dossier_oa)
      previous_candidats = candidats.deep_dup
      update_candidats(candidats, dossier)
      set_candidats_attribute(@dossier_oa, params[:champ_candidats], candidats.values) if previous_candidats != candidats
      set_text_attribute(@dossier_oa, params[:champ_synthese], synthese(candidats))
    end

    DN = 'Numéro DN'

    private

    def dossier_oa
      champ = dossier_field(dossier, @params[:champ_oa])
      raise StandardError, "Le champ #{@params[:champ_oa]} n'existe pas sur le dossier #{dossier.number}" if champ.blank?
      return unless champ.dossier.present? && @demarches_oa.include?(champ.dossier.demarche.number)

      champ.dossier
    end

    def update_candidats(candidats, dossier)
      dn_field = dossier_field(dossier, DN)
      raise "Numero DN vide dans dossier #{dossier.number}" if dn_field.blank?

      dn = dn_field.numero_dn.to_i
      candidat = candidats[dn] = candidats[dn] || {}
      update_candidat(candidat, dossier)
    end

    def update_candidat(candidat, dossier)
      candidat['Dossier'] = dossier.number
      candidat[PRESENCE] = candidat[PRESENCE]&.starts_with?('OA') ? 'OA+DE' : 'DE'
      DEMANDEUR.each { |field| candidat[field] ||= dossier.demandeur.send(symbolize(field)) }
      add_dn(candidat, dossier, '')
      CHAMPS_DE.each do |champ|
        value = dossier_field(dossier, champ).value
        candidat[champ] = value.match?(/^[0-9]+$/i) ? value.to_i : value
      end
      add_dn(candidat, dossier, ' du conjoint')
    end

    def add_dn(candidat, dossier, suffix)
      champ = dossier_field(dossier, "Numéro DN#{suffix}")
      return if champ.blank? || champ.numero_dn.blank?

      candidat["Numéro DN#{suffix}"] = champ.numero_dn.to_i
      candidat["Date de naissance#{suffix}"] = Date.iso8601(champ.date_de_naissance)
    end
  end
end
