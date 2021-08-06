# frozen_string_literal: true

namespace :dossiers do
  desc 'close dossiers where arrival date is after June 23'
  task close_obsolete: :environment do
    include Utils
    since = 10.days.ago
    demarche_id = 1054 # 1155 # 1054,
    close_date = Date.new(2021, 07, 5)
    start_date = Date.new(2021, 06, 29)
    demarche = DemarcheActions.get_demarche(demarche_id, 'cloture de dossier', 'clautier@idt.pf')
    count = 0
    count_all = 0
    DossierActions.on_dossiers(demarche_id, since) do |dossier|
      count_all += 1
      if dossier.state == 'accepte'
        date = Date.iso8601(dossier_field_value(dossier, "Date d'arrivée").value)
        if date > close_date || (DOUBLONS.include?(dossier.number) && date > start_date)
          count += 1
          puts "#{count}: Closing #{dossier.number} where arrival date is #{Date.iso8601(dossier_field_value(dossier, "Date d'arrivée").value)}"
          close_dossier(demarche, dossier)
        else
          puts "#{count_all}: Ignoring #{dossier.number}: #{Date.iso8601(dossier_field_value(dossier, "Date d'arrivée").value)}"
        end
      else
        puts "#{count_all}: Ignoring #{dossier.number}: #{Date.iso8601(dossier_field_value(dossier, "Date d'arrivée").value)}, #{dossier.state}"
      end
    end
  end

  # DOUBLONS = Set[
  #   78884, 79092, 79272, 79798, 79802, 80067, 80630, 80664, 80862, 81321, 81486, 81594, 81619, 81921, 82001, 82007, 82179,
  #   82387, 82569, 82572, 82689, 82768, 83002, 83227, 83267, 83321, 83380, 83431, 83671, 83680, 83708, 83718, 83764, 83776,
  #   83831, 83836, 83933, 84047, 84133, 84171, 84177, 84203, 84275, 84282, 84293, 84301, 84411, 84437, 84463, 84504, 84527,
  #   84545, 84566, 84570, 84623, 84639, 84673, 84711, 84840, 84962, 84973, 84980, 85031, 85047, 85056, 85098, 85169, 85275,
  #   85385, 85585, 85625, 85643, 85650, 85672, 85714, 85872, 85910, 85951, 86155, 86167, 86176, 86177, 86186, 86188, 86207,
  #   86257, 86338, 86597, 86629, 86673, 86688, 86750, 86780, 86787, 86806, 86812, 86828, 86835, 86846, 86870, 86906, 86907,
  #   86910, 86944, 86986, 87005, 87007, 87057, 87083, 87106, 87202, 87253, 87347, 87362, 87482, 87581, 87806, 87886, 87952,
  #   87980, 88099, 88104, 88427, 89011, 89278, 89325, 89602, 89683, 89912, 89972, 90256, 90523, ]
  DOUBLONS = Set[
    82533, 82825, 83103, 83246, 84163, 84272, 84343, 85369, 85843, 86237, 86400, 87065, 88279, 88407, 90043, 79802,
    80862, 82007, 82768, 83708, 84437, 84463, 84504, 84566, 84840, 84962, 84973, 85056, 86257, 79092, 80067, 82569,
    82572, 83718, 83933, 84133, 84293, 84527, 84639, 84673, 85047, 85098, 85650, 86186, 86629, 86806, 86846, 86870,
    86907, 86910, 87581, 87952, 90523, 80664, 83431, 83680, 84203, 84711, 86780, 86787, 86835, 87362, 87806, 88099,
    88104, 82001, 83764, 84047, 84411, 84570, 84980, 85169, 85951, 86177, 86188, 86750, 86986, 87005, 87007, 87980,
    89278, 83671, 84171, 84177, 84282, 87202, 89602, 83267, 84623, 86828, 89683, 81486, 81921, 82179, 82689, 84275,
    85031, 85714, 86207, 87106, 84545, 86906, 87253, 87482, 85625, 85872, 86338, 86812, 86944, 88427, 89011, 89325,
    89912, 83227, 83776, 89972, 85385, 86673, 86688, 85275, 78884, 83380, 79798, 82387, 87886, 87347, 79272, 90256,
    83831, 85910, 86176, 83321, 85585, 81619, 83002, 85672, 81594, 86155, 83836, 87083, 86167, 86597, 81321, 80630,
    85643, 84301, 87057
  ]

  CLOSE_MESSAGE_DOUBLON = <<~EOS
      Cher voyageur,

      Pour votre venue en Polynésie française, vous avez complété un nouveau dossier sanitaire suite au changement de réglementation.
      
      Cet ancien dossier va être clôturé par nos équipes. Vous n'avez rien à faire.
      Vous pouvez ignorez les messages à venir concernant ce dossier.
      
      Bon voyage 
      La plateforme Manava
      
      ---
      Dear traveler
      
      For your coming trip to french Polynesia you have completed a new health request following regulatory changes.
      
      This former application will now be closed by our teams. You have nothing to do.
      Please disregard coming notifications on it.
      
      Have a safe trip,
      The Manava team
  EOS

  CLOSE_MESSAGE = <<~EOS
    Cher voyageur,

    Les conditions d'entrée en Polynésie française ont changé depuis le 9 juin (décret N°525 CM du 13 mai 2020 modifié).
    Vous devez effectuer de nouveau les formalités au plus tard 6 jours avant le départ sur www.etis.pf 

    Vous aurez deux demandes à effectuer : 
    <ul><li>1.	une demande sanitaire ou demande motif impérieux (selon votre cas)</li> 
    <li>une demande Etis.</li></ul>

    Nota :
    <ul><li>Dans la demande Etis, si le site vous indique que votre numéro de passeport est déjà utilisé, effacez votre précédente demande Etis via le lien 'Gérer mon dossier' dans le bandeau bleu.</li>      
    <li>>Cette ancienne demande sera classée sans suite dans les prochains jours par nos équipes.Merci d'ignorer les notifications à venir sur cette demande.</li></ul> 

    La plateforme Manava

    --------------------------------------------------------------------

    Dear Traveler, 

    The conditions for entry into French Polynesia have changed since June 9 (decree N°525 CM of May 13, 2020 modified).
    Please go to www.etis.pf to fill-out new applications.

    You will have two applications to fill-out:
    <ul><li>Would the ETIS application says your passeport number is already used, you will have to delete the old application using ‘Manage my file’ link in the blue banner.</li>      
    <li>>This former health application will be cancelled ("classe sans suite") in the coming days by our team. Please disregard the coming notifications on it.</li></ul> 

    Regards
    The Manava platform
  EOS

  def send_close_message(demarche, dossier)
    message =  DOUBLONS.include?(dossier.number) ? CLOSE_MESSAGE_DOUBLON : CLOSE_MESSAGE
    puts "#{dossier.number}: #{DOUBLONS.include?(dossier.number) ? 'CLOSE_MESSAGE_DOUBLON' : 'CLOSE_MESSAGE'}"
    result = MesDemarches::Client.query(MesDemarches::Mutation::EnvoyerMessage,
                                        variables: {
                                          dossierId: dossier.id,
                                          instructeurId: demarche.instructeur,
                                          body: message,
                                          clientMutationId: 'dededed'
                                        })
    if result.errors&.present?
      puts(result.errors.map(&:message).join(','))
    end
  end

  def dossier_state(dossier)
    MesDemarches::Client.query(MesDemarches::Queries::DossierState, variables: { number: dossier.number }).data.dossier.state
  end

  def close_dossier(demarche, dossier)
    msg_sent = dossier.messages.find { |m| m.body.include?('Please disregard') }
    send_close_message(demarche, dossier) unless msg_sent
    DossierRepasserEnInstruction.new({}).change_state(demarche, dossier)
    DossierClasserSansSuite.new({ motivation: "Annulation ancien dossier suite à l'évolution des conditions sanitaires - canceling old application because of new sanitary measures" }).change_state(demarche, dossier)

  end
end
