# frozen_string_literal: true

require 'rails_helper'

# Smoke test pour s'assurer que la stack Hotwire (import maps + Turbo + Stimulus)
# est correctement servie sur une page publique (Devise sign_in).
# Pas de system test à ce stade : un simple GET + inspection du HTML rendu suffit.
RSpec.describe 'Hotwire smoke', type: :request do
  describe 'GET /users/sign_in' do
    before { get '/users/sign_in' }

    it 'répond 200 OK' do
      expect(response).to have_http_status(:ok)
    end

    it 'inclut un tag importmap-rails (script type="importmap")' do
      expect(response.body).to match(/<script[^>]+type=["']importmap["']/)
    end

    it 'pin @hotwired/turbo-rails dans la importmap' do
      expect(response.body).to include('@hotwired/turbo-rails')
    end

    it 'pin @hotwired/stimulus dans la importmap' do
      expect(response.body).to include('@hotwired/stimulus')
    end

    it "charge l'entrée application via la importmap (module preload ou import)" do
      # importmap-rails émet un modulepreload pour `application` et un import
      # ES module qui pointe vers /assets/application-<digest>.js
      expect(response.body).to match(%r{/assets/application[^"']*\.js})
    end

    it 'conserve le legacy Sprockets javascript_include_tag application' do
      # Le legacy stack (jQuery + le code maison) reste chargé en parallèle
      # via javascript_include_tag 'application' (script src classique, pas type=module)
      expect(response.body).to match(%r{<script[^>]+src=["'][^"']*/assets/application[^"']*\.js[^"']*["'](?![^>]*type=["']module)})
    end
  end
end
