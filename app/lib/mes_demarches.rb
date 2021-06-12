# frozen_string_literal: true

require 'graphql/client'
require 'graphql/client/http'

module MesDemarches
  # Configure GraphQL endpoint using the basic HTTP network adapter.
  host = ENV.fetch('GRAPHQL_HOST', 'https://www.mes-demarches.gov.pf')
  graphql_url = "#{host}/api/v2/graphql"
  HTTP = GraphQL::Client::HTTP.new(graphql_url) do
    def headers(_context)
      { Authorization: "Bearer #{ENV['GRAPHQL_BEARER']}" }
    end
  end
  pp HTTP

  def self.http(host)
    Rails.cache.fetch("#{host} http client") do
      graphql_url = "#{host}/api/v2/graphql"
      GraphQL::Client::HTTP.new(graphql_url) do
        lambda do # headers
          { Authorization: "Bearer #{ENV['GRAPHQL_BEARER']}" }
        end
      end
    end
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

  # list dossiers

  Queries = Client.parse <<-'GRAPHQL'
    query Demarche($demarche: Int!) {
      demarche(number: $demarche) {
        title
        number
        groupeInstructeurs {
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
          file {
              contentType
              byteSize
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
      }
      ... on CiviliteChamp {
          value
      }
      ... on MultipleDropDownListChamp {
          values
      }
    }

    fragment DossierInfo on Dossier {
      id
      number
      archived

      state
      datePassageEnConstruction
      datePassageEnInstruction
      dateTraitement
      dateDerniereModification
      motivation
      usager {
          email
      }
      traitements {
        instructeurEmail
			  processedAt
        state
        motivation
      }
      demandeur {
          ... on PersonnePhysique {
              civilite
              dateDeNaissance
              nom
              prenom
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
      groupeInstructeur {
        instructeurs {
          id
          email
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
            }
            champs {
              ...ChampInfo
              ... on RepetitionChamp {
                  champs {
                      ...ChampInfo
                  }
              }
              ... on DossierLinkChamp {
                stringValue
                dossier {
                  ...DossierInfo
                  annotations {
                      ...ChampInfo
                  }
                  champs {
                      ...ChampInfo
                      ... on RepetitionChamp {
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
    query Dossier($dossier: Int!) {
      dossier(number: $dossier) {
          ...DossierInfo
          annotations {
            ...ChampInfo
          }
          champs {
            ...ChampInfo
            ... on RepetitionChamp {
                champs {
                    ...ChampInfo
                }
            }
            ... on DossierLinkChamp {
              stringValue
              dossier {
                ...DossierInfo
                annotations {
                    ...ChampInfo
                }
                champs {
                    ...ChampInfo
                    ... on RepetitionChamp {
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
  GRAPHQL

  Mutation = Client.parse <<-'GRAPHQL'
    mutation EnvoyerMessage($dossierId: ID!, $instructeurId: ID!, $body: String!, $clientMutationId: String!) {
        dossierEnvoyerMessage(
            input: {
                dossierId: $dossierId,
                instructeurId: $instructeurId,
                body: $body,
                clientMutationId: $clientMutationId
            }) {
            clientMutationId
            errors {
                message
            }
        }
    }

  GRAPHQL
end
