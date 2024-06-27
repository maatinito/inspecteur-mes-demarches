# frozen_string_literal: true

CLOSE_MESSAGE_DOUBLON = <<~MSG.freeze
          Cher voyageur,
  #{'    '}
          Pour votre venue en Polynésie française, vous avez complété un nouveau dossier sanitaire suite au changement de réglementation.
      #{'    '}
          Cet ancien dossier va être clôturé par nos équipes. Vous n'avez rien à faire.
          Vous pouvez ignorez les messages à venir concernant ce dossier.
      #{'    '}
          Bon voyage#{' '}
          La plateforme Manava
      #{'    '}
          ---
          Dear traveler
      #{'    '}
          For your coming trip to french Polynesia you have completed a new health request following regulatory changes.
      #{'    '}
          This former application will now be closed by our teams. You have nothing to do.
          Please disregard coming notifications on it.
      #{'    '}
          Have a safe trip,
          The Manava team
MSG

CLOSE_MESSAGE = <<~MSG.freeze
  Cher voyageur,

  Les conditions d'entrée en Polynésie française ont changé depuis le 9 juin (décret N°525 CM du 13 mai 2020 modifié).
  Vous devez effectuer de nouveau les formalités au plus tard 6 jours avant le départ sur www.etis.pf#{' '}

  Vous aurez deux demandes à effectuer :#{' '}
  <ul><li>1.	une demande sanitaire ou demande motif impérieux (selon votre cas)</li>#{' '}
  <li>une demande Etis.</li></ul>

  Nota :
  <ul><li>Dans la demande Etis, si le site vous indique que votre numéro de passeport est déjà utilisé, effacez votre précédente demande Etis via le lien 'Gérer mon dossier' dans le bandeau bleu.</li>#{'      '}
  <li>>Cette ancienne demande sera classée sans suite dans les prochains jours par nos équipes.Merci d'ignorer les notifications à venir sur cette demande.</li></ul>#{' '}

  La plateforme Manava

  --------------------------------------------------------------------

  Dear Traveler,#{' '}

  The conditions for entry into French Polynesia have changed since June 9 (decree N°525 CM of May 13, 2020 modified).
  Please go to www.etis.pf to fill-out new applications.

  You will have two applications to fill-out:
  <ul><li>Would the ETIS application says your passeport number is already used, you will have to delete the old application using ‘Manage my file’ link in the blue banner.</li>#{'      '}
  <li>>This former health application will be cancelled ("classe sans suite") in the coming days by our team. Please disregard the coming notifications on it.</li></ul>#{' '}

  Regards
  The Manava platform
MSG

DOUBLONS = Set[
  82_533, 82_825, 83_103, 83_246, 84_163, 84_272, 84_343, 85_369, 85_843, 86_237, 86_400, 87_065, 88_279, 88_407, 90_043, 79_802,
  80_862, 82_007, 82_768, 83_708, 84_437, 84_463, 84_504, 84_566, 84_840, 84_962, 84_973, 85_056, 86_257, 79_092, 80_067, 82_569,
  82_572, 83_718, 83_933, 84_133, 84_293, 84_527, 84_639, 84_673, 85_047, 85_098, 85_650, 86_186, 86_629, 86_806, 86_846, 86_870,
  86_907, 86_910, 87_581, 87_952, 90_523, 80_664, 83_431, 83_680, 84_203, 84_711, 86_780, 86_787, 86_835, 87_362, 87_806, 88_099,
  88_104, 82_001, 83_764, 84_047, 84_411, 84_570, 84_980, 85_169, 85_951, 86_177, 86_188, 86_750, 86_986, 87_005, 87_007, 87_980,
  89_278, 83_671, 84_171, 84_177, 84_282, 87_202, 89_602, 83_267, 84_623, 86_828, 89_683, 81_486, 81_921, 82_179, 82_689, 84_275,
  85_031, 85_714, 86_207, 87_106, 84_545, 86_906, 87_253, 87_482, 85_625, 85_872, 86_338, 86_812, 86_944, 88_427, 89_011, 89_325,
  89_912, 83_227, 83_776, 89_972, 85_385, 86_673, 86_688, 85_275, 78_884, 83_380, 79_798, 82_387, 87_886, 87_347, 79_272, 90_256,
  83_831, 85_910, 86_176, 83_321, 85_585, 81_619, 83_002, 85_672, 81_594, 86_155, 83_836, 87_083, 86_167, 86_597, 81_321, 80_630,
  85_643, 84_301, 87_057
]

namespace :dossiers do
  desc 'close dossiers where arrival date is after June 23'
  task close_obsolete: :environment do
    include Utils
    since = 10.days.ago
    demarche_id = 1054 # 1155 # 1054,
    close_date = Date.new(2021, 7, 5)
    start_date = Date.new(2021, 6, 29)
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

  def send_close_message(demarche, dossier)
    message = DOUBLONS.include?(dossier.number) ? CLOSE_MESSAGE_DOUBLON : CLOSE_MESSAGE
    puts "#{dossier.number}: #{DOUBLONS.include?(dossier.number) ? 'CLOSE_MESSAGE_DOUBLON' : 'CLOSE_MESSAGE'}"
    result = MesDemarches.query(MesDemarches::Mutation::EnvoyerMessage,
                                variables: {
                                  dossierId: dossier.id,
                                  instructeurId: demarche.instructeur,
                                  body: message,
                                  clientMutationId: 'dededed'
                                })
    puts(result.errors.map(&:message).join(',')) if result.errors&.present?
  end

  def dossier_state(dossier)
    MesDemarches.query(MesDemarches::Queries::DossierState, variables: { number: dossier.number }).data.dossier.state
  end

  def close_dossier(demarche, dossier)
    msg_sent = dossier.messages.find { |m| m.body.include?('Please disregard') }
    send_close_message(demarche, dossier) unless msg_sent
    DossierRepasserEnInstruction.new({}).change_state(demarche, dossier)
    DossierClasserSansSuite.new({ motivation: "Annulation ancien dossier suite à l'évolution des conditions sanitaires - canceling old application because of new sanitary measures" }).change_state(
      demarche, dossier
    )
  end
end
