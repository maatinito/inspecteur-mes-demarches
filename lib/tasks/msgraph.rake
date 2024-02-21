# frozen_string_literal: true

namespace :msgraph do
  desc 'Schedule all cron jobs'
  task test: :environment do
    user = 'fe4b4f5f-7332-4b85-8153-34656ca4823d'
    password = 'BGD8Q~gJS196jCSu0OX9R_yINQ0Axyvc1aqk_aNC'
    tenant_id = '2df2715f-907b-4452-970f-c2c27c0924e4'

    file_id = '01O4YTKEWUC3DNNJL52BH3NONJOODHWJM7'

    connection = Faraday::Connection.new do |builder|
      builder.adapter Faraday.default_adapter
      builder.ssl.verify = true
      builder.ssl.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end

    context = MicrosoftKiotaAuthenticationOAuth::ClientCredentialContext.new(tenant_id, user, password)
    authentication_provider = MicrosoftGraphCore::Authentication::OAuthAuthenticationProvider.new(context, nil, ['https://graph.microsoft.com/.default'])
    adapter = MicrosoftGraph::GraphRequestAdapter.new(authentication_provider)
    client = MicrosoftGraph::GraphServiceClient.new(adapter)
    consultings = client.sites.get.resume.value.filter { |s| s.display_name =~ /Consulting/ }
    consultings.each do |site|
      r = client.sites.by_site_id(site.id).drives
      request_info = r.to_get_request_information
      fiber = Fiber.new do
        authentication_provider.authenticate_request(request_info).resume
        request = adapter.get_request_from_request_info(request_info)
        response = connection.run_request(request.http_method, request.path, request.body, request.headers)
        if response.success?
          drive = JSON.parse(response.body, object_class: OpenStruct).value.first
          r = client.sites.by_site_id(site.id).drives.by_drive_id(drive.id)
          URI.encode_www_form_component('Décompte de temps.xlsx')

          path = "https://graph.microsoft.com/v1.0/sites/#{site.id}/drives/#{drive.id}/items/#{file_id}/content"
          theaders = {
            Authorization: request.headers['Authorization'],
            Accept: '*/*'
          }
          response = Typhoeus.get(path, ssl_verifypeer: true, verbose: false, followlocation: true, headers: theaders)
          pp response.total_time if response.success?
          # response = connection.run_request(request.http_method, path, request.body, request.headers)
          # while response.status == 302
          #   response = connection.get(response.headers['location'], {})
          # end
          # pp response.status

          path = "https://graph.microsoft.com/v1.0/sites/#{site.id}/drives/#{drive.id}/root/children"
          response = connection.run_request(request.http_method, path, request.body, request.headers)
          result = JSON.parse(response.body) # , object_class: OpenStruct)
          file = result['value'].find { |object| object['name'] == 'Décompte de temps.xlsx' }
          if file
            pp file
          else
            puts 'File not found.'
          end
          directory = result['value'].find { |object| object['name'] == 'Projets' }
          if directory
            pp directory
          else
            puts 'File not found.'
          end
        end
      end
      fiber.resume
    end
  end
end
