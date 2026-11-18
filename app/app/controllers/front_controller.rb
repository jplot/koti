# frozen_string_literal: true

# Serves the built front's index.html for every path that is not the API, so the Vue router owns them.
class FrontController < ApplicationController
  allow_unauthenticated_access

  # The front's entry page.
  #
  # @return [void] 200 with index.html, or 404 when the front was not built into public/
  def show
    index = Rails.public_path.join('index.html')
    return head(:not_found) unless index.exist?

    # The entry page names the hashed assets of the current build: a browser must ask again after an upgrade.
    response.headers['Cache-Control'] = 'no-cache'
    send_file index, type: 'text/html', disposition: 'inline'
  end
end
