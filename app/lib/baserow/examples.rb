# frozen_string_literal: true

# Ce fichier contient des exemples d'utilisation de l'API Baserow
# Vous pouvez le supprimer ou l'adapter selon vos besoins

module Baserow
  module Examples
    class << self
      # Exemple de configuration initiale
      def setup
        # Ces valeurs doivent être définies dans l'environnement ou dans un fichier .env
        ENV['BASEROW_URL'] = 'https://api-baserow.mes-demarches.gov.pf'
        ENV['BASEROW_API_TOKEN'] = 'votre_token_par_defaut'
        ENV['BASEROW_TOKEN_TABLE'] = '123' # ID de la table contenant les tokens
      end

      # Exemple d'utilisation directe du client
      def client_example
        # Créer un client Baserow
        client = Baserow::Client.new(
          'https://api-baserow.mes-demarches.gov.pf',
          'votre_token_api'
        )

        # Obtenir une table spécifique
        table = client.get_table('42') # Remplacer par l'ID réel de votre table
        puts "Table: #{table['name']}"

        # Lister les champs d'une table
        fields = client.list_fields('42')
        puts "Champs: #{fields.map { |f| f['name'] }.join(', ')}"

        # Lister les lignes d'une table
        rows = client.list_rows('42')
        puts "Nombre de lignes: #{rows['count']}"
        puts "Première ligne: #{rows['results'].first}"

        # Créer une nouvelle ligne
        new_row = client.create_row('42', { 'field_1' => 'Valeur 1', 'field_2' => 'Valeur 2' })
        puts "Nouvelle ligne créée: #{new_row['id']}"

        # Mettre à jour une ligne
        updated_row = client.update_row('42', new_row['id'], { 'field_1' => 'Valeur mise à jour' })
        puts "Ligne mise à jour: #{updated_row['field_1']}"

        # Supprimer une ligne
        client.delete_row('42', new_row['id'])
        puts 'Ligne supprimée'
      end

      # Exemple d'utilisation de la classe Table
      def table_example
        # Utilisation avec la configuration
        setup

        # Accéder à une table spécifique avec la configuration par défaut
        contacts_table = Baserow::Config.table('42', nil, 'Contacts')

        # Accéder à une table spécifique avec une configuration nommée
        Baserow::Config.table('43', 'tftn', 'Planning')

        # Lister tous les contacts
        contacts = contacts_table.all
        puts "Nombre de contacts: #{contacts.size}"

        # Rechercher un contact par nom
        john_contacts = contacts_table.search('Nom', 'John')
        puts "Contacts contenant 'John': #{john_contacts.size}"

        # Trouver un contact par email exact
        email_contacts = contacts_table.find_by('Email', 'john.doe@example.com')
        puts "Contact avec cet email: #{email_contacts.first && email_contacts.first['Nom']}"

        # Créer un nouveau contact
        new_contact = contacts_table.create_row({
                                                  'Nom' => 'Jane Smith',
                                                  'Email' => 'jane.smith@example.com',
                                                  'Téléphone' => '+123456789'
                                                })
        puts "Nouveau contact créé: #{new_contact['id']}"

        # Mettre à jour un contact
        updated_contact = contacts_table.update_row(new_contact['id'], {
                                                      'Téléphone' => '+987654321'
                                                    })
        puts "Contact mis à jour: #{updated_contact['Téléphone']}"

        # Supprimer un contact
        contacts_table.delete_row(new_contact['id'])
        puts 'Contact supprimé'
      end
    end

    # Cette classe peut être utilisée comme n'importe quelle autre tâche d'inspection
    class BaserowIntegrationTask < InspectorTask
      def required_fields
        super + %i[baserow_table_id id_field]
      end

      def authorized_fields
        super + %i[config_baserow]
      end

      def process(demarche, dossier)
        super

        # Connexion à la table Baserow avec la configuration spécifiée
        config_name = @params[:config_baserow]
        table = Baserow::Config.table(@params[:baserow_table_id], config_name)

        # Recherche de l'enregistrement correspondant
        id_value = param_field(@params[:id_field]).value
        records = table.find_by('ID', id_value)

        if records.any?
          # Mettre à jour l'enregistrement existant
          record = records.first
          table.update_row(record['id'], {
                             'Statut' => dossier.state,
                             'Date de mise à jour' => Time.now.strftime('%Y-%m-%d')
                           })
          @msgs << "Enregistrement Baserow mis à jour: #{record['id']}"
        else
          # Créer un nouvel enregistrement
          new_record = table.create_row({
                                          'ID' => id_value,
                                          'Numéro de dossier' => dossier.number,
                                          'Statut' => dossier.state,
                                          'Date de création' => Time.now.strftime('%Y-%m-%d')
                                        })
          @msgs << "Nouvel enregistrement Baserow créé: #{new_record['id']}"
        end

        save_messages(@msgs.join("\n"))
      end
    end
  end
end
