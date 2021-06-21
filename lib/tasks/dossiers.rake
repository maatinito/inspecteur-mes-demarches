# frozen_string_literal: true

namespace :dossiers do
  desc 'close dossiers where arrival date is after June 23'
  task close_obsolete: :environment do
    include Utils
    since = 1.year.ago
    demarche_id = 1054 # 1155 # 1054
    close_date = Date.new(2021, 0o6, 23)
    demarche = DemarcheActions.get_demarche(demarche_id, 'cloture de dossier', 'clautier@idt.pf')
    DossierActions.on_dossiers(demarche_id, since) do |dossier|
      if dossier.state == 'en_construction' || dossier.state == 'en_instruction'
        date = Date.iso8601(dossier_field_value(dossier, "Date d'arrivée").value)
        if date > close_date || date.year < 2021
          puts "Closing #{dossier.number} where arrival date is #{Date.iso8601(dossier_field_value(dossier, "Date d'arrivée").value)}"
          close_dossier(demarche, dossier)
        else
          puts "Ignoring #{dossier.number}: #{Date.iso8601(dossier_field_value(dossier, "Date d'arrivée").value)}"
        end
      else
        puts "Ignoring #{dossier.number}: #{Date.iso8601(dossier_field_value(dossier, "Date d'arrivée").value)}, #{dossier.state}"
      end
    end
  end

  CLOSE_MESSAGE = "Bonjour,
      compte tenu de l’évolution des mesures d’entrée et de surveillance sanitaire des arrivants en Polynésie française dans le cadre de la lutte contre la covid-19 (arrêté N°525 CM du 13 mai 2020 modifié), votre demande sanitaire d’ENTREE en Polynésie française est invalidée. Il vous est nécessaire de créer un nouveau dossier avec une demande sanitaire sur https://www.etis.pf/, dans un délai minimum de 6 jours précédant le déplacement.
      Cette demande sera examinée selon la règlementation actuellement en vigueur.
      Attention: Les dossiers pour partir de Polynésie restent valables. Seul le retour change.
      Votre dossier n'est pas refusé: vous devez refaire un dossier en fonction des nouvelles mesures.
      Cordialement
      La plateforme Manava

      Hello,
      considering the evolution of the measures of entry and sanitary surveillance of the arrivals in French Polynesia within the framework of the fight against covid-19 (decree N°525 CM of May 13, 2020 modified), your sanitary request of entry in French Polynesia is invalidated. It is necessary to create a new file with a sanitary request on https://www.etis.pf/, at least 6 days before the trip.
      This application will be examined according to the regulations currently in force.
      Sincerely
      The Manava platform
    "

  def send_close_message(demarche, dossier)
    result = MesDemarches::Client.query(MesDemarches::Mutation::EnvoyerMessage,
                                        variables: {
                                          dossierId: dossier.id,
                                          instructeurId: demarche.instructeur,
                                          body: CLOSE_MESSAGE,
                                          clientMutationId: 'dededed'
                                        })
    puts(result.errors.map(&:message).join(',')) if result.errors&.present?
  end

  def dossier_state(dossier)
    MesDemarches::Client.query(MesDemarches::Queries::DossierState, variables: { number: dossier.number }).data.dossier.state
  end

  def close_dossier(demarche, dossier)
    DossierPasserEnInstruction.new({}).change_state(demarche, dossier) if dossier.state == 'en_construction'
    DossierClasserSansSuite.new({ motivation: "Evolution des mesures d'entrée en Polynésie française" }).change_state(demarche, dossier)
    send_close_message(demarche, dossier)
  end
end
