# frozen_string_literal: true

require 'graphql/client'
require 'graphql/client/http'

module MesDemarches
  # Custom HTTP adapter class to avoid nested method definitions
  class CustomHTTPAdapter < GraphQL::Client::HTTP
    def headers(_context)
      { Authorization: "Bearer #{ENV.fetch('GRAPHQL_BEARER', nil)}" }
    end

    def connection
      # Ne pas mettre en cache la connexion pour éviter les erreurs SSL
      # "can't modify frozen OpenSSL::SSL::SSLContext"
      conn = super
      conn.read_timeout = 60
      conn.open_timeout = 60
      # Réduire le keep-alive pour éviter la réutilisation de connexions fermées
      conn.keep_alive_timeout = 2
      conn
    end
  end

  # Configure GraphQL endpoint using the custom HTTP network adapter.
  host = ENV.fetch('GRAPHQL_HOST', 'https://www.mes-demarches.gov.pf')
  graphql_url = "#{host}/api/v2/graphql"
  HTTP = CustomHTTPAdapter.new(graphql_url)

  def self.http(host)
    # Ne pas mettre en cache le client HTTP pour éviter les erreurs SSL
    graphql_url = "#{host}/api/v2/graphql"
    CustomHTTPAdapter.new(graphql_url)
  end

  # Fetch latest schema on init, this will make a network request
  Schema = GraphQL::Client.load_schema(HTTP)

  # However, it's smart to dump this to a JSON file and load from disk
  #
  # Run it from a script or rake task
  #   GraphQL::Client.dump_schema(SWAPI::HTTP, "path/to/schema.json")
  #
  # Schema = GraphQL::Client.load_schema("path/to/schema.json")

  Client = GraphQL::Client.new(schema: Schema, execute: HTTP)

  def self.query(definition, variables: {}, context: {})
    max_retries = 3
    retry_count = 0
    success = false

    until success
      begin
        result = Client.query(definition, variables:, context:)
        success = true
      rescue StandardError => e
        retry_count += 1

        unless retryable_error?(e)
          Rails.logger.error("Non-retryable error querying Mes-Démarches: #{e.message}")
          raise e
        end

        if retry_count >= max_retries
          Rails.logger.error("Max retries (#{max_retries}) exceeded querying Mes-Démarches: #{e.message}")
          raise e
        end

        Rails.logger.warn("Attempt #{retry_count} failed querying Mes-Démarches: #{e.message}. Retrying in 1 second...")
        sleep 1
      end
    end
    result
  end

  def self.retryable_error?(error)
    error.message.include?('frozen OpenSSL::SSL::SSLContext') ||
      error.message.include?('Bad file descriptor') ||
      error.message.include?('wrong status line') ||
      error.is_a?(Errno::ECONNRESET) ||
      error.is_a?(Errno::EPIPE) ||
      error.is_a?(OpenSSL::SSL::SSLError)
  end
  private_class_method :retryable_error?

  # list dossiers

  Queries = Client.parse <<-GRAPHQL
    query Ping() {
       demarche(number: 828) { id }
    }

    query Demarche($demarche: Int!) {
      demarche(number: $demarche) {
        title
        number
        groupeInstructeurs {
          label
          instructeurs {
            id
            email
          }
        }
      }
    }

    query DossierId($number: Int!) {
      dossier(number: $number) {
        id
        number
      }
    }

    query Instructeurs($number: Int!) {
      dossier(number: $number) {
        instructeurs {
          id
        }
      }
    }

    query DossierState($number: Int!) {
      dossier(number: $number) {
        id
        state
      }
    }

    fragment ChampInfo on Champ {
      id
      label
      ... on TextChamp {
          value
      }
      ... on CheckboxChamp {
          value
      }
      ... on IntegerNumberChamp {
          value
      }
      ... on DecimalNumberChamp  {
          value
      }
      ... on DateChamp  {
          value
      }
      ... on LinkedDropDownListChamp {
          primaryValue
          secondaryValue
      }
      ... on PieceJustificativeChamp  {
          files {
              contentType
              checksum
              filename
              url
          }
          file {
              contentType
              checksum
              filename
              url
          }
          stringValue
      }
      ... on NumeroDnChamp  {
          dateDeNaissance
          numeroDn
      }
      ... on SiretChamp {
          stringValue
          etablissement {
             siret
             address { label }
             entreprise {
               siren
               nomCommercial
               raisonSociale
               formeJuridique
             }
             association {
               titre
             }
             libelleNaf
             naf
          }
      }
      ... on CiviliteChamp {
          value
      }
      ... on MultipleDropDownListChamp {
          values
      }
      ... on VisaChamp {
          stringValue
      }
      ... on ReferentielDePolynesieChamp {
          stringValue
          columns { name value }
      }
      ... on CommuneDePolynesieChamp {
          stringValue
          commune {
              name
              postalCode
              island
              archipelago
          }
      }
      ... on CodePostalDePolynesieChamp {
          stringValue
          commune {
              name
              postalCode
              island
              archipelago
          }
      }
    }

    fragment DossierInfo on Dossier {
      id
      number
      state
      archived
      datePassageEnConstruction
      datePassageEnInstruction
      dateTraitement
      dateDerniereModification
      dateDepot
      motivation
      prenomMandataire
      nomMandataire
      deposeParUnTiers
      usager {
          email
      }
      groupeInstructeur {
        label
      }
      instructeurs {
        email
      }
      traitements {
        instructeurEmail
			  processedAt
        state
      }
      demarche {
        revision {
          id
          datePublication
        }
      }
      demandeur {
          ... on PersonnePhysique {
              civilite
              nom
              prenom
              email
          }
          ... on PersonneMorale {
              siret
              naf
              libelleNaf
              adresse
              numeroVoie
              typeVoie
              nomVoie
              complementAdresse
              codePostal
              localite
              entreprise {
                siren
                capitalSocial
                numeroTvaIntracommunautaire
                formeJuridique
                formeJuridiqueCode
                nomCommercial
                raisonSociale
                siretSiegeSocial
                codeEffectifEntreprise
                dateCreation
                nom
                prenom
              }
              association {
                rna
                titre
                objet
                dateCreation
                dateDeclaration
                dateDeclaration
              }
          }
      }
    }

    query DossiersModifies($demarche: Int!, $since: ISO8601DateTime!, $cursor: String) {
      demarche(number: $demarche) {
        dossiers(updatedSince: $since, after: $cursor) {
          pageInfo {
              endCursor
              hasNextPage
          }
          nodes {
            ...DossierInfo
            annotations {
              ...ChampInfo
               ... on RepetitionChamp {
                  rows {
                    champs {
                      ...ChampInfo
                      ... on DossierLinkChamp {
                          stringValue
                      }
                    }
                  }
                  champs {
                      ...ChampInfo
                  }
              }
            }
            champs {
              ...ChampInfo
              ... on DossierLinkChamp {
                stringValue
              }
              ... on RepetitionChamp {
                  rows {
                    champs {
                      ...ChampInfo
                      ... on DossierLinkChamp {
                          stringValue
                      }
                    }
                  }
                  champs {
                      ...ChampInfo
                  }
              }
              ... on DossierLinkChamp {
                stringValue
                dossier {
                  demarche { number }
                  ...DossierInfo
                  annotations {
                      ...ChampInfo
                      ... on RepetitionChamp {
                          rows {
                            champs {
                              ...ChampInfo
                            }
                          }
                      }
                  }
                  champs {
                      ...ChampInfo
                      ... on RepetitionChamp {
                          rows {
                            champs {
                              ...ChampInfo
                            }
                          }
                      }
                  }
                }
              }
            }
          }
        }
      }
    }
    query Dossier($dossier: Int!) {
      dossier(number: $dossier) {
          state
          demarche { number }
          ...DossierInfo
          annotations {
            ...ChampInfo
              ... on RepetitionChamp {
                  rows {
                    champs {
                      ...ChampInfo
                      ... on DossierLinkChamp {
                          stringValue
                      }
                    }
                  }
                  champs {
                      ...ChampInfo
                  }
              }
          }
          champs {
            ...ChampInfo
            ... on RepetitionChamp {
                  rows {
                    champs {
                      ...ChampInfo
                      ... on DossierLinkChamp {
                          stringValue
                      }
                    }
                  }
                champs {
                    ...ChampInfo
                }
            }
            ... on DossierLinkChamp {
              stringValue
              dossier {
                demarche { number }
                ...DossierInfo
                annotations {
                    ...ChampInfo
                }
                champs {
                    ...ChampInfo
                    ... on RepetitionChamp {
                        rows {
                          champs {
                            ...ChampInfo
                          }
                        }
                        champs {
                            ...ChampInfo
                        }
                    }
                }
              }
            }
          }
        }
      }

    fragment RevisionInfo on Revision {
      id
      datePublication
      champDescriptors {
        id
        label
        description
        required
        __typename
        ... on DropDownListChampDescriptor {
          options
          otherOption
        }
        ... on MultipleDropDownListChampDescriptor {
          options
        }
        ... on RepetitionChampDescriptor {
          champDescriptors {
            id
            label
            description
            required
            __typename
            ... on DropDownListChampDescriptor {
              options
            }
            ... on MultipleDropDownListChampDescriptor {
              options
            }
          }
        }
      }
      annotationDescriptors {
        id
        label
        description
        required
        __typename
        ... on DropDownListChampDescriptor {
          options
          otherOption
        }
        ... on MultipleDropDownListChampDescriptor {
          options
        }
        ... on RepetitionChampDescriptor {
          champDescriptors {
            id
            label
            description
            required
            __typename
            ... on DropDownListChampDescriptor {
              options
            }
            ... on MultipleDropDownListChampDescriptor {
              options
            }
          }
        }
      }
    }

    query DemarcheRevision($demarche: Int!) {
      demarche(number: $demarche) {
        title
        number
        draftRevision {
          ...RevisionInfo
        }
        publishedRevision {
          ...RevisionInfo
        }
      }
    }
  GRAPHQL
end
